/**
 * Unit tests for repository mocks used in isolation.
 */
@isTest
public class MockRepositoryTests {
    
    // Mock repository implementation for testing
    public class MockLoanRepository implements ILoanRepository {
        private Map<Id, Loan__c> storedLoans = new Map<Id, Loan__c>();
        
        public void save(Loan__c loan) {
            storedLoans.put(loan.Id, loan);
        }
        
        public void saveAll(List<Loan__c> loans) {
            for (Loan__c loan : loans) {
                save(loan);
            }
        }
        
        public Loan__c findById(Id id) {
            return storedLoans.get(id);
        }
        
        public List<Loan__c> findAllById(Set<Id> ids) {
            List<Loan__c> result = new List<Loan__c>();
            for (Id id : ids) {
                Loan__c loan = storedLoans.get(id);
                if (loan != null) {
                    result.add(loan);
                }
            }
            return result;
        }
        
        public List<Loan__c> findByAccountId(Id accountId) {
            List<Loan__c> result = new List<Loan__c>();
            for (Loan__c loan : storedLoans.values()) {
                if (loan.Account__c == accountId) {
                    result.add(loan);
                }
            }
            return result;
        }
        
        public void deleteRecord(Loan__c loan) {
            storedLoans.remove(loan.Id);
        }
        
        public void deleteAll(List<Loan__c> loans) {
            for (Loan__c loan : loans) {
                deleteRecord(loan);
            }
        }
    }
    
    @isTest
    static void testMockRepositoryImplementation() {
        MockLoanRepository mockRepo = new MockLoanRepository();
        
        // Create test data
        Account testAccount = new Account(Name = 'Test Account');
        insert testAccount;
        
        Loan__c testLoan = new Loan__c(
            Account__c = testAccount.Id,
            Loan_Type__c = 'Secured',
            Loan_Amount__c = 10000,
            Loan_Term__c = 6,
            Interest_Rate__c = 5.0
        );
        
        // Test save
        mockRepo.save(testLoan);
        
        // Test findById
        Loan__c retrievedLoan = mockRepo.findById(testLoan.Id);
        System.assertEquals(testLoan.Id, retrievedLoan.Id);
        System.assertEquals(testLoan.Loan_Type__c, retrievedLoan.Loan_Type__c);
        
        // Test findAllById
        Set<Id> loanIds = new Set<Id>{testLoan.Id};
        List<Loan__c> retrievedLoans = mockRepo.findAllById(loanIds);
        System.assertEquals(1, retrievedLoans.size());
        System.assertEquals(testLoan.Id, retrievedLoans[0].Id);
        
        // Test findByAccountId
        List<Loan__c> loansByAccount = mockRepo.findByAccountId(testAccount.Id);
        System.assertEquals(1, loansByAccount.size());
        System.assertEquals(testLoan.Id, loansByAccount[0].Id);
        
        // Test delete
        mockRepo.deleteRecord(testLoan);
        Loan__c deletedLoan = mockRepo.findById(testLoan.Id);
        System.assertEquals(null, deletedLoan);
    }
    
    // LoanService tests removed as service has been refactored into command/query services.
}
