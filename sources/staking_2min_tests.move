#[test_only]
module test_addr::krz_staking_2min_tests {
    use std::signer;
    use std::vector;
    use aptos_framework::timestamp;
    use aptos_framework::coin;
    use aptos_framework::account;
    use test_addr::krz_coin_test_v4::{Self, Kryzel};
    use test_addr::krz_staking_2min_v4;

    // Test Constants
    const INITIAL_BALANCE: u64 = 1000000000000;  // 1K tokens
    const STAKE_AMOUNT: u64 = 100000000000;      // 100 tokens
    const REVENUE_AMOUNT: u64 = 10000000000;     // 10 tokens

    fun setup_test(aptos_framework: &signer, admin: &signer, user: &signer) {
        account::create_account_for_test(signer::address_of(aptos_framework));
        timestamp::set_time_has_started_for_testing(aptos_framework);
        
        let start_time = 1000000000;
        timestamp::update_global_time_for_test_secs(start_time);
        
        account::create_account_for_test(signer::address_of(admin));
        account::create_account_for_test(signer::address_of(user));
        
        krz_coin_test::initialize_for_test(admin);
        coin::register<Kryzel>(user);
        coin::register<Kryzel>(admin);
        
        // Just mint once - no need for extra tokens for restake
        krz_coin_test::mint(admin, signer::address_of(user), INITIAL_BALANCE);
        krz_coin_test::mint(admin, signer::address_of(admin), REVENUE_AMOUNT * 2);
        
        krz_staking_2min::initialize_for_test(admin);
    }

    #[test(aptos_framework = @0x1, admin = @test_addr, user = @0x123)]
    public entry fun test_restake_flow(aptos_framework: &signer, admin: &signer, user: &signer) {
        setup_test(aptos_framework, admin, user);
        
        // Get initial balance
        let initial_balance = coin::balance<Kryzel>(signer::address_of(user));
        
        // Initial stake
        krz_staking_2min::stake(user, STAKE_AMOUNT);
        
        // Balance should be reduced by STAKE_AMOUNT
        let after_stake = coin::balance<Kryzel>(signer::address_of(user));
        assert!(after_stake == initial_balance - STAKE_AMOUNT, 0);
        
        // Wait for ACTIVE
        timestamp::fast_forward_seconds(120);
        krz_staking_2min::update_status(user);
        
        // Restake - should NOT change balance
        let before_restake = coin::balance<Kryzel>(signer::address_of(user));
        krz_staking_2min::restake(user, 0);
        let after_restake = coin::balance<Kryzel>(signer::address_of(user));
        assert!(before_restake == after_restake, 1); // Balance unchanged
        
        // Verify stake is back to IN_PROCESS
        let stakes = krz_staking_2min::get_user_stakes(signer::address_of(user));
        assert!(vector::length(&stakes) == 1, 2); // Still just 1 stake
    }
} 