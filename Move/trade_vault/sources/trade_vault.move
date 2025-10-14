module trade_vault::trade_vault;

use std::string::String;



public struct VaultCreated has copy, drop {
    vault_id: ID,
    from: address,
    to: address,
    amount: u64,
    asset_type: String,
    timestamp: u64,
}

/// Vault = escrow object holding info about locked funds
public struct Vault has key, store {
    id: UID,
    from: address,          // Buyer (payer)
    to: address,            // Seller (receiver)
    asset_type: String,     // "SUI", "USDC", "NFT"
    amount: u64,            // Amount locked
    locked: bool,           // True while escrow active
    created_at: u64,
}

/// UnlockKey = single-use key object. Possession of this object + buyer signer allows unlock.
public struct UnlockKey has key, store {
    id: UID,
    vault_id: ID,
}

public struct VaultRegistry has key, store {
    id: UID,
    vaults: vector<ID>,
}

public struct VaultUnlocked has copy, drop {
    vault_id: ID,
    timestamp: u64,
}

public struct VaultStorage has key, store {
    id: UID,
    deals: vector<ID>
}

public struct Verifier has key {
    id: UID,
    owner: address,
    name_service_domain: String,   // e.g., "john.sui"
    reputation_score: u8,          // Track reliability
    total_approved: u64,           // Stats for history
}

public struct Deal has key {
    id: UID,
    buyer: address,
    seller: address,
    amount: u64,
    vault_ids: vector<ID>,           // References to vaults (not embedded)
    status: String,
    verifier_approvals: vector<address>,  // Track which verifiers approved
    created_at: u64,
}