import Foundation
import Testing
@testable import CodexCost

struct CostFormattingTests {
    @Test func positiveSubCentCostsDoNotLookFree() {
        #expect(dollars(Decimal(string: "0.0027093")!) == "<$0.01")
        #expect(dollars(Decimal(string: "0.009999")!) == "<$0.01")
        #expect(dollars(0) == "$0.00")
        #expect(dollars(Decimal(string: "0.01")!) == "$0.01")
        #expect(dollars(Decimal(string: "0.218609784")!) == "$0.22")
    }
}
