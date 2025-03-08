module test_addr::kryzel_coin_v7 {
    use std::string;
    use std::signer;
    use aptos_framework::coin::{Self, BurnCapability, MintCapability};

    struct Kryzel {}                            

    struct CapStore has key {
        mint_cap: MintCapability<Kryzel>,
        burn_cap: BurnCapability<Kryzel>
    }

    const E_NO_ADMIN: u64 = 1;

    public entry fun initialize(admin: &signer) {
        let (burn_cap, freeze_cap, mint_cap) = coin::initialize<Kryzel>(
            admin,
            string::utf8(b"Kryzel"),
            string::utf8(b"KRZ"),
            6,
            true
        );

        move_to(admin, CapStore {
            mint_cap,
            burn_cap
        });
        coin::destroy_freeze_cap(freeze_cap);
    }

    public entry fun register(user: &signer) {
        coin::register<Kryzel>(user);
    }

    public entry fun mint(admin: &signer, to: address, amount: u64) acquires CapStore {
        let admin_addr = signer::address_of(admin);
        assert!(exists<CapStore>(admin_addr), E_NO_ADMIN);

        let caps = borrow_global<CapStore>(admin_addr);
        let coins = coin::mint(amount, &caps.mint_cap);
        coin::deposit(to, coins);
    }

    public entry fun transfer(from: &signer, to: address, amount: u64) {
        let coins = coin::withdraw<Kryzel>(from, amount);
        coin::deposit<Kryzel>(to, coins);
    }

}

