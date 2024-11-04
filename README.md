# DATA MODEL

# A custom object Loan__c is used to store details of a loan application and its status
# The Loan__c object has the following custom fields
    ○ Loan_Type__c – Picklist
    ○ Loan_Amount__c - Currency
    ○ Loan_Term__c – Number
    ○ Interest_Rate__c - Percent
    ○ Loan_Status__c – Picklist
    ○ Principal_Plus_Interest__c - Number
    ○ Account__c – Master-detail relationship with account object

# A custom object Payment_Plan__c is used to store details for paying back the borrowed amount with the interest rate
# The Payment_Plan__c object has the following custom fields
    ○ Payment_Status__c – Picklist
    ○ Payment_Deadline__c - Date
    ○ Payment_Amount__c - Currency
    ○ Loan__c - Master-detail relationship with the loan object

# The component holds five fields and a save button.
    ○ Loan Type
    ○ Loan Amount
    ○ Loan Term
    ○ Interest Rate
    ○ Loan Status
# When a Loan is created `Principal_Plus_Interest__c` is calculated upon saving, adding `Interest Rate` to the `Loan Amount`.

# The component should display an error message if the user enters a `Loan Term` that exceeds the maximum allowed for the selected `Loan Type`.
    ○ EXAMPLE 1: (`VALID`)
    ○ Loan Type: Secured
    ○ Loan Amount: 30 000
    ○ Loan Term: 6 (The maximum allowed for Secured Loans)
    ○ Interest Rate: 5%
    ○ Loan Status: Approved

    ○ EXAMPLE 1: (`INVALID`)
    ○ Loan Type: Secured
    ○ Loan Amount: 30 000
    ○ Loan Term: 7 (Exceeds maximum allowed for Secured Loans)
    ○ Interest Rate: 5%
    ○ Loan Status: Approved

# To create Payment Plan records when a Loan is created. The number of `Payment Plan` records will be determined by the `Loan Term`, and their total amount will be equal to the Loan’s `Principal_Plus_Interest__c` field value. Each `Payment Plan` should have a deadline that is the 1st day of the next month, starting from the Loan creation date.
   `BREAKDOWN`
    1. Number of Payment Plan Records: The number of records is determined by the Loan Term (e.g., if the Loan Term is 6 months, create 6 Payment Plan records).
    2. Payment Amount Calculation: The total amount of all Payment Plan records should be equal to the Loan's `Principal_Plus_Interest__c` field. Thus, each Payment Plan's `Payment_Amount__c` will be calculated by dividing the `Principal_Plus_Interest__c` by the `Loan Term`.
    3. Payment Deadlines: The first Payment Plan deadline will be the 1st day of the next month after the Loan creation date, and each subsequent deadline will be the 1st day of the following month.

#If you want to comment on an error or give an idea, I'm open to comments and critical thinking on the current repository.

#You can contact me via LinkedIn.

![chatuml-diagram](https://github.com/user-attachments/assets/a622f19b-b968-419a-8efa-d1bfe2512384)

