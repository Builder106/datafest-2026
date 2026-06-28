library(testthat)
library(DBI)
library(duckdb)

TRANSPORT_Q <- c(
  "In the past 12 months, has lack of transportation kept you from medical appointments or from getting medications?",
  "In the past 12 months, has lack of transportation kept you from meetings, work, or from getting things needed for daily living?"
)

# Runs the same transport classification SQL used in 03_journey.R against
# a synthetic in-memory DuckDB and returns the result.
classify_transport <- function(sdoh_rows) {
  con <- dbConnect(duckdb::duckdb(), ":memory:")
  on.exit(dbDisconnect(con, shutdown = TRUE), add = TRUE)

  dbWriteTable(con, "sdoh", sdoh_rows)

  q1 <- gsub("'", "''", TRANSPORT_Q[1])
  q2 <- gsub("'", "''", TRANSPORT_Q[2])

  dbExecute(con, sprintf("
    CREATE TABLE patient_transport AS
    WITH transport AS (
      SELECT PatientDurableKey, AnswerText, COUNT(*) AS n
      FROM sdoh
      WHERE Domain = 'Transportation Needs'
        AND DisplayName IN ('%s', '%s')
        AND PatientDurableKey IS NOT NULL
      GROUP BY PatientDurableKey, AnswerText
    )
    SELECT
      PatientDurableKey,
      MAX(CASE WHEN AnswerText = 'Yes' THEN 1 ELSE 0 END)                                    AS transport_yes,
      MAX(CASE WHEN AnswerText = 'No'  THEN 1 ELSE 0 END)                                    AS transport_no,
      MAX(CASE WHEN AnswerText IN ('Patient declined','Patient unable to answer') THEN 1 ELSE 0 END) AS transport_declined
    FROM transport
    GROUP BY PatientDurableKey;", q1, q2))

  dbExecute(con, "ALTER TABLE patient_transport ADD COLUMN transport_status VARCHAR;")
  dbExecute(con, "
    UPDATE patient_transport
    SET transport_status = CASE
      WHEN transport_yes      = 1 THEN 'barrier'
      WHEN transport_no       = 1 THEN 'no_barrier'
      WHEN transport_declined = 1 THEN 'declined'
      ELSE 'other'
    END;")

  dbGetQuery(con, "SELECT PatientDurableKey, transport_status
                   FROM patient_transport
                   ORDER BY PatientDurableKey;")
}

row <- function(pid, answer) {
  data.frame(
    PatientDurableKey = pid,
    Domain            = "Transportation Needs",
    DisplayName       = TRANSPORT_Q[1],
    AnswerText        = answer,
    stringsAsFactors  = FALSE
  )
}

test_that("Yes answer → barrier", {
  result <- classify_transport(row(1L, "Yes"))
  expect_equal(result$transport_status, "barrier")
})

test_that("No answer → no_barrier", {
  result <- classify_transport(row(2L, "No"))
  expect_equal(result$transport_status, "no_barrier")
})

test_that("Patient declined → declined", {
  result <- classify_transport(row(3L, "Patient declined"))
  expect_equal(result$transport_status, "declined")
})

test_that("Patient unable to answer → declined", {
  result <- classify_transport(row(4L, "Patient unable to answer"))
  expect_equal(result$transport_status, "declined")
})

test_that("Yes beats No when a patient has both (any-Yes wins)", {
  rows <- rbind(row(5L, "Yes"), row(5L, "No"))
  result <- classify_transport(rows)
  expect_equal(result$transport_status, "barrier")
})

test_that("multiple patients are classified independently", {
  rows <- rbind(
    row(10L, "Yes"),
    row(11L, "No"),
    row(12L, "Patient declined")
  )
  result <- classify_transport(rows)
  expect_equal(result[result$PatientDurableKey == 10L, "transport_status"], "barrier")
  expect_equal(result[result$PatientDurableKey == 11L, "transport_status"], "no_barrier")
  expect_equal(result[result$PatientDurableKey == 12L, "transport_status"], "declined")
})

test_that("rows from a non-transport domain are excluded", {
  rows <- rbind(
    data.frame(
      PatientDurableKey = 20L,
      Domain            = "Food Insecurity",
      DisplayName       = "Some food question",
      AnswerText        = "Yes",
      stringsAsFactors  = FALSE
    ),
    row(20L, "No")
  )
  result <- classify_transport(rows)
  expect_equal(result$transport_status, "no_barrier")
})
