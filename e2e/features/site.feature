Feature: DataFest-2026 research site

  Scenario: Page loads with headline statistics
    Given I am on the research site
    Then the page title contains "Ride Is the Missing Treatment"
    And the adjusted odds ratio "3.17" is visible
    And the ED rate "1.94" is visible

  Scenario: Patient journey visualization is rendered
    Given I am on the research site
    Then the journey SVG is visible
    And the transport barrier bar chart is visible

  Scenario: Three robustness check cards are present
    Given I am on the research site
    Then all 3 robustness check cards are present

  Scenario: Deliverable links are present
    Given I am on the research site
    Then the judges writeup link is present
    And the presentation deck link is present
