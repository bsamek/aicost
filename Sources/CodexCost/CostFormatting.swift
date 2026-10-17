import Foundation

func dollars(_ value: Decimal) -> String {
    if value > 0 && value < Decimal(string: "0.01")! { return "<$0.01" }
    return value.formatted(.currency(code: "USD").locale(Locale(identifier: "en_US")))
}
