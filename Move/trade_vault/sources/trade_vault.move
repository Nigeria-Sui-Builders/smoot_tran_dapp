module trade_vault::trade_vault;

use std::string::String;
use sui::clock::{Clock, timestamp_ms};
use sui::coin::{Self, Coin};
use sui::sui::SUI;
use sui::event;
use sui::balance::{Self, Balance};

/// Error codes
const ENotBuyer: u64 = 101;
const EAmountMismatch: u64 = 102;
const ENotVerifierOwner: u64 = 103;
const EVerifierNotActive: u64 = 104;
const EAlreadyApproved: u64 = 105;
const EAlreadyRejected: u64 = 106;
const ENotVerified: u64 = 107;
const EVaultNotAvailable: u64 = 108;
const EInvalidStatus: u64 = 109;

/// Deal status enum
public enum DealStatus has copy, drop, store {
Pending,      // Buyer made offer, waiting for verifiers
Verified,     // Verifiers approved
Completed,    // Transaction completed
Disputed,     // Verifiers rejected
Cancelled,    // Deal cancelled
}

/// Vault = Seller's listing (what they're selling)
public struct Vault has key {
    id: UID,
    seller: address,              // Original seller who created the vault
    owner: address,               // Current owner of the vault (changes after sale)
    asset_type: String,           // What's being sold (e.g., "NFT", "Token")
    amount: u64,                  // Amount/quantity
    price: u64,                   // Price in SUI
    balance: Balance<SUI>,        // Holds the actual funds when locked
    is_available: bool,           // Can buyers purchase?
    description: String,          // Description of item
    created_at: u64,
}

/// Deal = A purchase transaction between buyer and seller
public struct Deal has key {
    id: UID,
    vault_id: ID,                 // Which vault is being purchased
    buyer: address,               // Who's buying
    seller: address,              // Who's selling
    amount: u64,                  // Purchase amount
    status: DealStatus,
    verifier_approvals: vector<address>,
    verifier_rejections: vector<address>,
    required_verifications: u8,
    created_at: u64,
    updated_at: u64,
}

/// Registry to track all vaults
public struct VaultRegistry has key {
    id: UID,
    vaults: vector<ID>,
}

/// Verifier = trusted third-party who can approve deals
public struct Verifier has key {
    id: UID,
    owner: address,
    name_service_domain: String,  // Must have SuiNS
    reputation_score: u8,
    total_approved: u64,
    total_rejected: u64,
    is_active: bool,
    created_at: u64,
}

/// Verifier Registry - tracks all verifiers
public struct VerifierRegistry has key {
    id: UID,
    verifiers: vector<address>,
    min_reputation: u8,
}

/// Events
public struct VaultCreated has copy, drop {
    vault_id: ID,
    seller: address,
    asset_type: String,
    amount: u64,
    price: u64,
    timestamp: u64,
}

public struct DealCreated has copy, drop {
    deal_id: ID,
    vault_id: ID,
    buyer: address,
    seller: address,
    amount: u64,
    timestamp: u64,
}

public struct VerificationSubmitted has copy, drop {
    deal_id: ID,
    verifier: address,
    approved: bool,
    timestamp: u64,
}

public struct DealCompleted has copy, drop {
    deal_id: ID,
    vault_id: ID,
    buyer: address,
    seller: address,
    amount: u64,
    timestamp: u64,
}

public struct VerifierRegistered has copy, drop {
    verifier: address,
    name_service_domain: String,
    timestamp: u64,
}

/// Initialize registries
fun init(ctx: &mut TxContext) {
    let vault_registry = VaultRegistry {
        id: object::new(ctx),
        vaults: vector[],
    };
    transfer::share_object(vault_registry);

    let verifier_registry = VerifierRegistry {
        id: object::new(ctx),
        verifiers: vector[],
        min_reputation: 50,
    };
    transfer::share_object(verifier_registry);
}

/// Seller creates a vault (listing) with items to sell
public entry fun create_vault(
    registry: &mut VaultRegistry,
    asset_type: String,
    amount: u64,
    price: u64,
    description: String,
    clock: &Clock,
    ctx: &mut TxContext
) {
    let sender = ctx.sender();
    let timestamp = timestamp_ms(clock);
    let vault_uid = object::new(ctx);
    let vault_id = object::uid_to_inner(&vault_uid);

    let vault = Vault {
        id: vault_uid,
        seller: sender,
        owner: sender,            // Initially, owner is the seller
        asset_type: asset_type,
        amount,
        price,
        balance: balance::zero(),
        is_available: true,
        description,
        created_at: timestamp,
    };

    registry.vaults.push_back(vault_id);

    event::emit(VaultCreated {
        vault_id,
        seller: sender,
        asset_type: vault.asset_type,
        amount,
        price,
        timestamp,
    });

    transfer::share_object(vault);
}

/// Buyer initiates a purchase from a vault
public entry fun initiate_purchase(
    vault: &mut Vault,
    payment: Coin<SUI>,
    required_verifications: u8,
    clock: &Clock,
    ctx: &mut TxContext
) {
    let sender = ctx.sender();
    let timestamp = timestamp_ms(clock);

    assert!(vault.is_available, EVaultNotAvailable);
    assert!(coin::value(&payment) == vault.price, EAmountMismatch);

    let deal_uid = object::new(ctx);
    let deal_id = object::uid_to_inner(&deal_uid);
    let vault_id = object::uid_to_inner(&vault.id);

    // Lock the vault
    vault.is_available = false;

    // Store payment in vault
    let payment_balance = coin::into_balance(payment);
    balance::join(&mut vault.balance, payment_balance);

    let deal = Deal {
        id: deal_uid,
        vault_id,
        buyer: sender,
        seller: vault.seller,
        amount: vault.price,
        status: DealStatus::Pending,
        verifier_approvals: vector[],
        verifier_rejections: vector[],
        required_verifications,
        created_at: timestamp,
        updated_at: timestamp,
    };

    event::emit(DealCreated {
        deal_id,
        vault_id,
        buyer: sender,
        seller: vault.seller,
        amount: vault.price,
        timestamp,
    });

    transfer::share_object(deal);
}

/// Register as a verifier (must have SuiNS)
public fun register_verifier_internal(
    registry: &mut VerifierRegistry,
    name_service_domain: String,
    clock: &Clock,
    ctx: &mut TxContext
): ID {
    let sender = ctx.sender();
    let timestamp = timestamp_ms(clock);

    let verifier = Verifier {
        id: object::new(ctx),
        owner: sender,
        name_service_domain: name_service_domain,
        reputation_score: 100,
        total_approved: 0,
        total_rejected: 0,
        is_active: true,
        created_at: timestamp,
    };

    let verifier_id = object::id(&verifier);
    registry.verifiers.push_back(sender);

    event::emit(VerifierRegistered {
        verifier: sender,
        name_service_domain: verifier.name_service_domain,
        timestamp,
    });

    transfer::share_object(verifier);
    verifier_id
}

/// Entry function wrapper for registering verifier
public entry fun register_verifier(
    registry: &mut VerifierRegistry,
    name_service_domain: String,
    clock: &Clock,
    ctx: &mut TxContext
) {
    register_verifier_internal(registry, name_service_domain, clock, ctx);
}

/// Verifier approves or rejects a deal
public entry fun verify_deal(
    deal: &mut Deal,
    verifier: &mut Verifier,
    approved: bool,
    clock: &Clock,
    ctx: &mut TxContext
) {
    let sender = ctx.sender();
    assert!(sender == verifier.owner, ENotVerifierOwner);
    assert!(verifier.is_active, EVerifierNotActive);

    let deal_id = object::uid_to_inner(&deal.id);
    let timestamp = timestamp_ms(clock);

    // Check if verifier already voted
    assert!(!deal.verifier_approvals.contains(&sender), EAlreadyApproved);
    assert!(!deal.verifier_rejections.contains(&sender), EAlreadyRejected);

    if (approved) {
        deal.verifier_approvals.push_back(sender);
        verifier.total_approved = verifier.total_approved + 1;

        // Check if enough verifications
        if (deal.verifier_approvals.length() >= (deal.required_verifications as u64)) {
            deal.status = DealStatus::Verified;
        };
    } else {
        deal.verifier_rejections.push_back(sender);
        verifier.total_rejected = verifier.total_rejected + 1;
        deal.status = DealStatus::Disputed;
    };

    deal.updated_at = timestamp;

    event::emit(VerificationSubmitted {
        deal_id,
        verifier: sender,
        approved,
        timestamp,
    });
}

/// Complete the deal after verification (transfer ownership to buyer)
public entry fun complete_deal(
    deal: &mut Deal,
    vault: &mut Vault,
    clock: &Clock,
    ctx: &mut TxContext
) {
    let sender = ctx.sender();
    assert!(sender == deal.buyer || sender == deal.seller, ENotBuyer);
    assert!(deal.status == DealStatus::Verified, ENotVerified);

    let timestamp = timestamp_ms(clock);
    deal.status = DealStatus::Completed;
    deal.updated_at = timestamp;

    // Transfer funds from vault to seller
    let payment = coin::from_balance(balance::withdraw_all(&mut vault.balance), ctx);
    transfer::public_transfer(payment, vault.seller);

    // Transfer ownership of the vault to the buyer
    vault.owner = deal.buyer;
    vault.is_available = false;

    event::emit(DealCompleted {
        deal_id: object::uid_to_inner(&deal.id),
        vault_id: object::uid_to_inner(&vault.id),
        buyer: deal.buyer,
        seller: deal.seller,
        amount: deal.amount,
        timestamp,
    });
}

/// Cancel deal and refund buyer (if not verified yet)
public entry fun cancel_deal(
    deal: &mut Deal,
    vault: &mut Vault,
    clock: &Clock,
    ctx: &mut TxContext
) {
    let sender = ctx.sender();
    assert!(sender == deal.buyer, ENotBuyer);
    assert!(
        deal.status == DealStatus::Pending || deal.status == DealStatus::Disputed,
        EInvalidStatus
    );

    deal.status = DealStatus::Cancelled;
    deal.updated_at = timestamp_ms(clock);

    // Refund buyer
    let refund = coin::from_balance(balance::withdraw_all(&mut vault.balance), ctx);
    transfer::public_transfer(refund, deal.buyer);

    // Make vault available again
    vault.is_available = true;
}

/// Deactivate verifier
public entry fun deactivate_verifier(
    verifier: &mut Verifier,
    ctx: &mut TxContext
) {
    let sender = ctx.sender();
    assert!(sender == verifier.owner, ENotVerifierOwner);
    verifier.is_active = false;
}

/// View functions (getter methods)
public fun get_vault_price(vault: &Vault): u64 {
    vault.price
}

public fun get_vault_seller(vault: &Vault): address {
    vault.seller
}

public fun get_vault_owner(vault: &Vault): address {
    vault.owner
}

public fun is_vault_available(vault: &Vault): bool {
    vault.is_available
}

public fun get_vault_amount(vault: &Vault): u64 {
    vault.amount
}

public fun get_deal_buyer(deal: &Deal): address {
    deal.buyer
}

public fun get_deal_seller(deal: &Deal): address {
    deal.seller
}

public fun get_deal_amount(deal: &Deal): u64 {
    deal.amount
}

public fun get_verifier_reputation(verifier: &Verifier): u8 {
    verifier.reputation_score
}

public fun get_verifier_domain(verifier: &Verifier): String {
    verifier.name_service_domain
}