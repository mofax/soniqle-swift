#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

import Soniqle

let taskExampleJSON = """
{
    "from": ["users", "u"],
    "select": [
        "$u.id",
        ["as", "$u.name", "customer_name"],
        ["as", ["count", "$o.id"], "order_count"]
    ],
    "joins": [
        ["left", ["orders", "o"], ["=", "$o.user_id", "$u.id"]]
    ],
    "where": [
        "and",
        ["=", "$u.active", ":active"],
        [">=", "$o.created_at", ":startDate"],
        ["in", "$o.status", ":statuses"]
    ],
    "groupBy": ["$u.id", "$u.name"],
    "having": [">", ["count", "$o.id"], ":minimumOrderCount"],
    "orderBy": [
        ["@order_count", "desc"]
    ],
    "limit": ":limit"
}
"""

let fixedDate = Date(timeIntervalSince1970: 1_700_000_000)

func taskExampleParameters() -> [String: SQLValue] {
    [
        "active": .bool(true),
        "startDate": .date(fixedDate),
        "statuses": .array([.string("paid"), .string("shipped")]),
        "minimumOrderCount": .int(5),
        "limit": .int(100),
    ]
}
