# LoanSalesforce Project

This repository contains a Salesforce implementation for managing loan applications with payment plans, following Domain-Driven Design (DDD) principles.

## Deployment Notes

### Post-Deploy Setup (Required For A Clean Demo)

Follow these steps after deployment so a fresh org looks like the reference demo:

1. Assign the permission set:
   - Setup -> Permission Sets -> `Fin_Tech_User` -> Manage Assignments -> add your user.
   - This grants `ApiEnabled`, delete on `Loan__c`, and sets custom tabs to visible.
2. Ensure the Fin Tech app shows the custom tabs:
   - App Manager -> Fin Tech -> Edit -> Navigation Items -> make sure the custom tabs are in Selected Items.
   - In the app header, click the pencil icon on the nav bar and choose "Reset" (user nav personalization can hide tabs).
3. Ensure the Account record page includes the Loans UI:
   - Lightning App Builder -> Account Record Page -> add the `accountLoansContainer` LWC.
   - Activate the page for the Fin Tech app or the intended profiles.
4. Ensure the Prepay Loan action is available on Loan records:
   - Object Manager -> Loan__c -> Page Layouts -> add Quick Action `Prepay Loan` to the actions bar.
   - If you use a custom Lightning Record Page for Loan, add the action to its Highlights Panel.

### Schedule Payment Reminders (Recommended)
Scheduling is org-specific, so the recommended approach is to schedule `LoanPaymentReminderJob` after deployment.

You can schedule from **Setup -> Apex Classes -> Schedule Apex** or run Execute Anonymous:

```apex
String cronExp = '0 0 8 * * ?';
System.schedule('Loan Payment Reminder Daily 8AM', cronExp, new LoanPaymentReminderJob());
```

## Features Implemented

### 1. Custom Lightning Component
- Created a custom Lightning Web Component (LWC) with 4 fields: Loan Type, Loan Amount, Loan Term, Interest Rate
- Loan Status is system-controlled and automatically set to "Pending" when the Loan record is created; hidden on the Loan layout/edit UI but visible in the Account loans list
- Save button creates a new loan record with entered values
- Client-side validation enforces maximum loan terms:
  - Secured loans: maximum 6 months
  - Unsecured loans: maximum 12 months
- Error messages displayed when invalid terms are entered
- Component structure is: AccountLoansContainer (parent) -> LoanForm (child) for better organization on the account page

### 2. Loan Term Limits
- Maximum loan term enforced based on loan type
- Validation prevents saving with invalid terms

### 3. Payment Plan Records Creation
- Payment Plan records created asynchronously (Queueable) based on loan term value
- Number of records equals loan term value
- Total of all Payment Plan record's Payment_Amount__c equals Loan's Principal_Plus_Interest__c
- Payment Plan records created with 1st day of next month as deadline

### 4. Loan Term Adjustment (Hybrid: Flow + Apex)
- Flow detects changes to Loan_Term__c on update and displays user-friendly errors for invalid term changes
- Apex handles complex logic of adjusting Payment_Plan__c records
- Trigger enqueues Apex adjustment when Interest_Rate__c or Loan_Amount__c changes (Loan_Term__c changes are handled by the Flow)
- Loan term cannot be reduced below the number of completed payment plans (validated on update)
- If loan term is reduced, excess Payment_Plan__c records deleted
- If loan term is increased, new Payment_Plan__c records created
- Total Payment_Amount__c of all Payment_Plan__c records always equals Principal_Plus_Interest__c

**Implementation Note:** The system uses a hybrid approach with both Flow and Apex for payment plan adjustments. The Flow (`Invocable_LoanTermAdjustment.flow-meta.xml`) enforces UI term limits for Secured (6) and Unsecured (12) and invokes `LoanTermAdjustmentInvoker.adjustLoanTerms` to adjust payment plans when the term changes. The Loan trigger enqueues adjustments only when Interest_Rate__c or Loan_Amount__c changes (to avoid duplicate adjustments when Loan_Term__c changes in the UI).

### 5. Loan Status Automation
- Trigger in Payment_Plan__c.Payment_Status__c
- If all Payment_Plan__c records marked as "Completed", set loan's Loan_Status__c to "Closed"
- If any Payment_Plan__c records fail, set loan status to "Failed"

### 6. Loan Repayment Notifications
- Apex scheduled job scans Payment_Plan__c.Payment_Deadline__c field
- Sends email reminder to borrower exactly 5 days before each payment deadline
- Sends follow-up email if payment is missed and still not completed after a 3-day grace period
- Borrower selection: the first Contact (ordered by CreatedDate) with a non-empty Email on the Account is used; if none have Email, no email is sent

### 7. Over/Underpayment Protection
- BYPASS field added to Payment_Plan__c object
- Validation rule prevents manual edits unless BYPASS__c is checked
- If users edit some open payment amounts, the system adjusts the remaining open payments so totals still match Principal_Plus_Interest__c
- If all open payment amounts are edited and totals do not match the remaining balance, the update is blocked

### 8. Loan Prepayment Functionality
- Reusable Lightning component and Apex logic that accepts a Loan recordId as input
- Calculates remaining balance (sum of non-Completed Payment_Plan__c records)
- Marks all pending Payment_Plan__c records as Completed
- Updates Loan__c status to Closed
- Displays a success toast with remaining balance information
- Supports being triggered from both a Loan record page action and a row-level action in the Account -> Loans related list
- Not embedded in the loan creation form
- **Integration**: Upon prepayment, recalculates interest based on actual loan term and adjusts payment plans accordingly

### 9. Loan Restructuring
- Detects when Loan_Term__c is increased or decreased after loan creation
- Detects when Interest_Rate__c is changed after loan creation
- Creates or removes Payment_Plan__c records to match new loan term when extending term
- Recalculates Principal_Plus_Interest__c when interest rate changes
- Adjusts all existing Payment_Plan__c records to ensure their total equals the recalculated amount
- Handles both term extension and interest rate changes in a single operation when both change simultaneously
- Maintains consistency and avoids double recalculation
- Follows DDD principles with business logic in Domain layer and orchestration in Service layer
- Trigger-based detection with proper recursion guards and bulk safety

## Data Model

### Loan__c Object
- Loan_Type__c - Picklist
- Loan_Amount__c - Currency
- Loan_Term__c - Number
- Interest_Rate__c - Percent
- Loan_Status__c - Picklist (values: Pending, Under Review, Failed, Closed)
- Principal_Plus_Interest__c - Number
- Account__c - Master-detail relationship with account object

### Payment_Plan__c Object
- Payment_Status__c - Picklist (values: Pending, Completed, Failed)
- Payment_Deadline__c - Date
- Payment_Amount__c - Currency
- Loan__c - Master-detail relationship with the loan object

## Architecture

This implementation follows Domain-Driven Design (DDD) principles with the following layers:
- **Presentation Layer**: Lightning Web Component / Controllers
- **Application Layer**: Command and Query services (LoanCommandService, PaymentPlanCommandService, LoanQueryService, PaymentPlanQueryService)
- **Domain Layer**: Business logic (LoanDomain, PaymentPlanDomain)
- **Infrastructure Layer**: Jobs, repositories, and triggers
- **Repository Layer**: Data access (LoanRepository, PaymentPlanRepository)

## How to Use the Application

### Step 1: Navigate to an Account Record
1. Go to the Salesforce homepage
2. Navigate to the Accounts tab
3. Select an existing account or create a new one
4. Click on the account record to view its details

### Step 2: Create a Loan Using the LoanForm Component
1. On the Account record page, locate the "LoanForm" component (usually in the "Related" section or as a custom component)
2. Fill in the following fields:
   - Loan Type: Select either "Secured" or "Unsecured"
   - Loan Amount: Enter the loan amount
   - Loan Term: Enter the loan term (maximum 6 months for Secured, 12 months for Unsecured)
   - Interest Rate: Enter the annual interest rate
   - Loan Status: This field is system-controlled and automatically set to "Pending" (hidden on the Loan layout/edit UI but visible in the Account loans list)
3. Click the "Create" button
4. If validation passes, the loan will be created and you'll see a success message with the loan ID

### Step 3: View the Created Loan
1. After saving, the newly created loan will appear in the "Loans" related list on the Account record page
2. Click on the loan record to view its details
3. The loan record will show all entered information including the calculated Principal_Plus_Interest__c
4. The loan record will be named in a meaningful format like "Loan Secured - 30000" instead of showing just the ID

### Step 4: View Payment Plans
1. When you click on a loan record, you'll see the "Payment Plans" related list
2. The number of payment plan records will match the Loan Term entered
3. Each payment plan will show:
   - Payment Amount (calculated as Principal_Plus_Interest__c divided by Loan Term)
   - Payment Deadline (1st day of each month starting from the 1st day of the next month)
   - Payment Status (initially "Pending")
4. Payment Plan records will be named in a meaningful format like "Payment 1 of 3 for Secured" instead of showing just the ID

### Step 5: Monitor Loan Status
1. As payment plans are marked as completed, the loan status will automatically update to "Closed"
2. If any payment plan fails, the loan status will update to "Failed"
3. If any payment plan is not "Pending" (and none are "Failed"), the loan status will be "Under Review"
4. All status changes are tracked and displayed in the loan record

### Step 6: Receive Notifications
1. The system will automatically schedule email notifications:
   - 5 days before each payment deadline
   - If a payment is missed, a follow-up email will be sent
2. These notifications are sent to the first Contact (ordered by CreatedDate) with a non-empty Email on the Account

## Implementation Details

### Payment Plan Creation
When a loan is created:
1. Payment Plan records are created based on the loan term
2. Each Payment Plan's Payment_Amount__c is calculated as Principal_Plus_Interest__c divided by Loan_Term
3. Payment deadlines are set to the 1st day of each month starting from the 1st day of the next month after loan creation
4. Any remainder from the division is distributed to ensure the total matches exactly

### Status Management
- Payment Plan Status: "Pending" when created, "Completed" when paid, "Failed" when missed
- Loan Status: "Pending" initially, "Under Review" when any payment plan is not "Pending" and none failed, "Closed" when all payments completed, "Failed" when any payment fails

### Validation
- Client-side validation in Lightning component
- Server-side validation in LoanCommandService (loan term, positive loan amount, non-negative interest rate)
- Overpayment protection with BYPASS field and validation rule

### Optional Async Loan Creation (Integration)
For integrations that prefer async processing, `LoanController.createLoanAsync` enqueues `LoanQueueable` and returns a `jobId` in the response. This is optional and not used by the UI LWC.

### Data Retrieval
- The AccountLoansContainer LWC component retrieves data via UI API GraphQL (LDS)
- Rendering and refresh use `refreshGraphQL` with an imperative GraphQL fallback
- Loan create and delete use LDS (`createRecord` and `deleteRecord`)

**UI API Note:** Ensure UI API GraphQL is enabled in the org (Setup -> GraphQL API).

## Testing Instructions

### `Test 1:` Loan Creation with Valid Terms
1. Navigate to an Account record in Salesforce
2. Use the LoanForm component to create a new loan with:
   - Loan Type: Secured
   - Loan Amount: 30000
   - Loan Term: 6 (maximum for Secured loans)
   - Interest Rate: 5%
3. Click Create
4. Verify the loan is created successfully
5. Check that the loan appears in the "Loans" related list (UI API GraphQL / LDS retrieval)
6. Verify that the Principal_Plus_Interest__c is correctly calculated (30000 + 1500 = 31500)

### `Test 2:` Loan Creation with Invalid Terms
1. Navigate to an Account record in Salesforce
2. Use the LoanForm component to create a new loan with:
   - Loan Type: Secured
   - Loan Amount: 30000
   - Loan Term: 7 (exceeds maximum for Secured loans)
   - Interest Rate: 5%
3. Click Create
4. Verify that an error message is displayed: "Loan term exceeds maximum allowed for Secured loans (6 months)."
5. Verify that no loan record is created

### Test 3: Payment Plan Creation
1. Create a new loan with Loan Term = 6 months
2. After saving, navigate to the loan record
3. Check the "Payment Plans" related list
4. Verify that exactly 6 payment plan records are created
5. Verify that each payment plan has:
   - Payment Amount = Principal_Plus_Interest__c / Loan Term (31500 / 6 = 5250)
   - Payment Deadline = 1st day of each month starting from 1st day of next month
   - Payment Status = "Pending"

### `Test 4:` Loan Status Automation
1. Create a loan with Loan Term = 3 months
2. Navigate to the loan record and then to the Payment Plans related list
3. Manually update all 3 payment plans to "Completed" status
4. Verify that the loan status automatically updates to "Closed"

### `Test 5:` Loan Status Failure Detection
1. Create a loan with Loan Term = 3 months
2. Navigate to the loan record and then to the Payment Plans related list
3. Manually update one payment plan to "Failed" status
4. Verify that the loan status automatically updates to "Failed"

### `Test 6:` Overpayment Protection
1. Create a new loan with Loan Term = 2 months
2. Navigate to the Payment Plans related list
3. Try to manually edit a payment plan's Payment_Amount__c to exceed the Principal_Plus_Interest__c
4. Verify that a validation error is displayed: "Payment amount cannot be edited unless BYPASS__c is checked."
5. If you edit all open payment amounts with BYPASS__c checked and the total does not match the remaining balance, verify the error: "Payment amounts must total the remaining balance (X)."

### `Test 7:` Payment Plan Adjustment
1. Create a loan with Loan Term = 3 months
2. Navigate to the loan record
3. Update the Loan_Term__c field to 5 months
4. Verify that:
   - 2 new payment plans are created
   - Open (non-completed) payment plans are recalculated; completed plans retain their amounts
   - All payment plans have correct deadlines
   - Total payment amount still equals Principal_Plus_Interest__c
5. Attempt to reduce Loan_Term__c below the number of completed payment plans
6. Verify that the update is blocked with an error

**Test Note:** The payment plan adjustment uses a hybrid approach: the Flow (`Invocable_LoanTermAdjustment`) validates and invokes Apex for Loan_Term__c changes, and the Loan trigger enqueues the Apex adjustment when only Interest_Rate__c or Loan_Amount__c changes.

### `Test 8:` Loan Repayment Notifications (Immediate Testing)
1. Create a new loan with Loan Term = 3 months
2. Navigate to the loan record and then to the Payment Plans related list
3. Verify that 3 payment plan records are created with deadlines 1 month apart
4. **Immediate Testing Method:**
   - Go to Setup -> Developer Console -> Debug -> Open Execute Anonymous Window
   - Paste the following code and click "Execute":
```apex
LoanPaymentReminderJob job = new LoanPaymentReminderJob();
job.execute(null);
```
     
5. Ensure the Account has a Contact with a valid Email
6. Set a Payment_Deadline__c date to exactly 5 days from today for a non-completed payment plan
7. Run the job and check your email inbox for the upcoming payment reminder email
8. Set a Payment_Deadline__c date to 3 days in the past for a non-completed payment plan (grace-period follow-up)
9. **Immediate Testing Method:**
   - Again, Go to Setup -> Developer Console -> Debug -> Open Execute Anonymous Window
   - Paste the following code and click "Execute":
```apex
LoanPaymentReminderJob job = new LoanPaymentReminderJob();
job.execute(null);
```
     
10. Check your email inbox for the missed payment reminder emails sent to the borrower

### `Test 9:` Loan Prepayment Functionality
1. Create a new loan with Loan Term = 3 months
2. Navigate to the loan record
3. Verify that 3 payment plan records are created with "Pending" status
4. Click the "Actions" dropdown in the loan record header
5. Select "Prepay Loan" from the menu `If the Quick Action button is missing, just added via LRP or Page Layout`
6. Confirm the prepayment in the dialog that appears
7. Verify that:
   - All 3 payment plans are marked as "Completed"
   - The loan status is updated to "Closed"
   - A success toast notification appears
   - The remaining balance is displayed in the toast message
   - **Behavior**: Interest is recalculated based on actual loan term, and the Principal_Plus_Interest__c field is adjusted accordingly
8. Verify that the loan can no longer be modified through normal processes since it's closed

### `Test 10:` Loan Restructuring
1. Create a new loan with Loan Term = 3 months and Interest Rate = 5%
2. Navigate to the loan record
3. Verify that 3 payment plan records are created with correct amounts
4. Update the Loan_Term__c field to 5 months
5. Verify that:
   - 2 new payment plans are created
   - Open (non-completed) payment plans are recalculated; completed plans retain their amounts
   - All payment plans have correct deadlines
   - Total payment amount still equals Principal_Plus_Interest__c
6. Update the Interest_Rate__c field to 7%
7. Verify that:
   - Principal_Plus_Interest__c is recalculated correctly (Loan_Amount + (Loan_Amount * 7%))
   - All existing payment plans are adjusted to match the new total
   - New payment plans (if any) are also adjusted to maintain correct total
8. Update both Loan_Term__c to 4 months and Interest_Rate__c to 6% simultaneously
9. Verify that:
   - Payment plans are adjusted for both changes in a single operation
   - All payment amounts sum to the recalculated Principal_Plus_Interest__c
   - No double recalculation occurs
   - Loan status remains consistent throughout the process


## Future Enhancements

This implementation will be extended with additional features including:
- Enhanced reporting capabilities
- Approval workflows
- Advanced notification preferences
- Data archiving for historical records

![chatuml-diagram](https://github.com/user-attachments/assets/a622f19b-b968-419a-8efa-d1bfe2512384)
