//
//  Copyright RevenueCat Inc. All Rights Reserved.
//
//  Licensed under the MIT License (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//      https://opensource.org/licenses/MIT
//
//  StoreKitConfigTestCase+Extensions.swift
//
//  Created by Nacho Soto on 11/17/22.

import Nimble
@testable import RevenueCat
import StoreKit
import XCTest

@available(iOS 15.0, tvOS 15.0, macOS 12.0, watchOS 8.0, *)
extension StoreKitConfigTestCase {

    @_disfavoredOverload
    @discardableResult
    func simulateAnyPurchase(
        productID: String? = nil,
        finishTransaction: Bool = false
    ) async throws -> SK2Transaction {
        let product: SK2Product?

        if let productID = productID {
            product = try await self.fetchSk2Product(productID)
        } else {
            product = nil
        }

        return try await self.simulateAnyPurchase(product: product,
                                                  finishTransaction: finishTransaction).underlyingTransaction
    }

    /// - Parameters:
    ///   - product: An optional `SK2Product` to be purchased. If `nil`, a default product will be fetched.
    ///   - finishTransaction: A Boolean flag indicating whether to call `finish()`
    ///   on the transaction after a successful purchase.
    ///   - retryPurchaseOnUserCancelled: A Boolean flag indicating whether to
    ///   retry the purchase up to 3 times if the user cancels. The retry backoff interval is equal to the number of
    ///   attempts in seconds (1s, then 2s, etc.). This is helpful in CI environments where StoreKit may not be
    ///   ready to make a purchase immediately. In this case, it sometimes returns a `userCancelled` PurchaseResult
    ///   for purchases.
    /// - Returns: `SK2Transaction` ater the purchase succeeded.
    @discardableResult
    func simulateAnyPurchase(
        product: SK2Product? = nil,
        finishTransaction: Bool = false,
        retryPurchaseOnUserCancelled: Bool = false
    ) async throws -> StoreKit.VerificationResult<SK2Transaction> {
        let productToPurchase: SK2Product
        if let product = product {
            productToPurchase = product
        } else {
            productToPurchase = try await self.fetchSk2Product()
        }

        var result: Product.PurchaseResult?

        var attempts = 0
        let maxAttempts = 3
        while attempts < maxAttempts {
            result = try await productToPurchase.purchase()

            switch result {
            case .success, .pending, nil:
                attempts = .max // Exit the loop. Breaking here only breaks out of the switch, not the while loop
            case .userCancelled:
                attempts += 1
                try await Task.sleep(nanoseconds: UInt64(attempts) * 1_000_000_000)
                continue
            default:
                attempts = .max // Exit the loop. Breaking here only breaks out of the switch, not the while loop
            }
        }

        let unwrappedResult = try XCTUnwrap(result, "Purchase attempt did not yield a result")
        let verificationResult = try XCTUnwrap(
            unwrappedResult.verificationResult, "Purchase did not succeed: \(unwrappedResult)"
        )

        if finishTransaction {
            await verificationResult.underlyingTransaction.finish()
        }

        return verificationResult
    }

    /// - Returns: `SK2Transaction` after the purchase succeeded. This transaction is automatically finished.
    func createTransactionWithPurchase(product: SK2Product? = nil) async throws -> Transaction {
        return try await self.simulateAnyPurchase(product: product, finishTransaction: true).underlyingTransaction
    }

    func fetchSk2Product(_ productID: String = StoreKitConfigTestCase.productID) async throws -> SK2Product {
        let products: [SK2Product] = try await StoreKit.Product.products(for: [productID])
        return try XCTUnwrap(products.first)
    }

    @available(iOS 15.0, tvOS 15.0, watchOS 8.0, macOS 12.0, *)
    func fetchSk2StoreProduct(_ productID: String = StoreKitConfigTestCase.productID) async throws -> SK2StoreProduct {
        return SK2StoreProduct(sk2Product: try await self.fetchSk2Product(productID))
    }

    func createTransaction(
        productID: String? = nil,
        finished: Bool,
        environment: StoreEnvironment = .sandbox
    ) async throws -> StoreTransaction {
        let product: SK2Product?

        if let productID = productID {
            product = try await self.fetchSk2Product(productID)
        } else {
            product = nil
        }

        let result = try await self.simulateAnyPurchase(product: product,
                                                        finishTransaction: finished)
        return StoreTransaction(
            sk2Transaction: result.underlyingTransaction,
            jwsRepresentation: result.jwsRepresentation,
            environmentOverride: environment
        )
    }

}

@available(iOS 14.0, tvOS 14.0, macOS 11.0, watchOS 7.0, *)
extension StoreKitConfigTestCase {

    /// Updates `SKTestSession.storefront` and waits for `Storefront.current` to reflect the change
    /// This is necessary because the change is aynchronous within `StoreKit`, and otherwise code that depends
    /// on the change might not see it in time, resulting in race conditions and flaky tests.
    func changeStorefront(
        _ new: String,
        file: FileString = #fileID,
        line: UInt = #line
    ) async throws {
        self.testSession.storefront = new

        try await asyncWait(
            description: "Storefront change not detected",
            timeout: .seconds(1),
            pollInterval: .milliseconds(100)
        ) {
            await Storefront.currentStorefront?.countryCode == new
        }
    }

}

@available(iOS 14.0, tvOS 14.0, macOS 11.0, watchOS 7.0, *)
extension StoreKitConfigTestCase {

    static let productID = "com.revenuecat.monthly_4.99.1_week_intro"
    static let consumableProductId = "com.revenuecat.consumable"
    static let nonConsumableProductId = "lifetime"
    static let nonRenewableProductId = "com.revenuecat.non_renewable"

}

@available(iOS 14.0, tvOS 14.0, macOS 11.0, watchOS 7.0, *)
fileprivate extension StoreKitConfigTestCase {

    enum Error: Swift.Error {

        case noProductsFound
        case multipleProductsFound

    }

}

@available(iOS 14.0, tvOS 14.0, macOS 11.0, watchOS 7.0, *)
extension ProductsFetcherSK1 {

    func product(withIdentifier identifier: String) async throws -> StoreProduct {
        let products = try await self.products(withIdentifiers: Set([identifier]))

        switch products.count {
        case 0: throw StoreKitConfigTestCase.Error.noProductsFound
        case 1: return StoreProduct.from(product: products.first!)
        default: throw StoreKitConfigTestCase.Error.multipleProductsFound
        }
    }

}

@MainActor
@available(iOS 15.0, tvOS 15.0, watchOS 8.0, macOS 12.0, *)
extension ProductsFetcherSK2 {

    func product(withIdentifier identifier: String) async throws -> StoreProduct {
        let products = try await self.products(identifiers: Set([identifier]))

        switch products.count {
        case 0: throw StoreKitConfigTestCase.Error.noProductsFound
        case 1: return StoreProduct.from(product: products.first!)
        default: throw StoreKitConfigTestCase.Error.multipleProductsFound
        }
    }

}
