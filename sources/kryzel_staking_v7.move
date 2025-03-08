module test_addr::kryzel_staking_v7  {
    use std::signer;
    use std::vector;
    use aptos_framework::coin::{Self, Coin};
    use aptos_framework::timestamp;
    use aptos_framework::event::{Self, EventHandle};
    use aptos_framework::account;
    use test_addr::kryzel_coin_v7::Kryzel;
    
    // Constants for timing
    const ONE_DAY: u64 = 120;      // 2 minutes = 1 day (for testing)
    const UTC_NOON: u64 = 60;      // 1 minute = 12:00 UTC (for testing)
    const STAKE_DURATION: u64 = 120; // 2 minutes for testing

    // Error constants
    const ERROR_NO_STAKE_FOUND: u64 = 1;
    const ERROR_INVALID_INDEX: u64 = 2;
    const ERROR_INVALID_STATUS: u64 = 3;
    const EINVALID_OWNER: u64 = 0;
    const EINVALID_STATUS: u64 = 1;
    const EINVALID_AMOUNT: u64 = 2;
    const EINSUFFICIENT_BALANCE: u64 = 3;
    const ERROR_NO_EXPIRED_STAKES: u64 = 4;

    // Time constants (in seconds)
    const SECONDS_PER_DAY: u64 = 86400;  // Real 24 hours in seconds
    const UTC_MIDNIGHT: u64 = 0;         // 00:00 UTC
    const EXPIRY_DAYS: u64 = 1;            // Reduce to 1 day to avoid overflow
    const MIN_DEPOSIT_INTERVAL: u64 = 120;  // 2 minutes
    const ACTIVATION_TIME: u64 = 180;       // 3 minutes
    const EXPIRY_TIME: u64 = 240;          // 4 minutes (reduced from 5)

    const DEFAULT_RESTAKE_BONUS_BPS: u64 = 500;  // 5% default
    const BPS_DENOMINATOR: u64 = 10000;          // Base for basis points (100% = 10000)
    const MAX_RESTAKE_BONUS_BPS: u64 = 1000;     // Max 10% bonus

    const PRECISION: u128 = 1000000;  // 6 decimals for precision

    // Replace these constants
    // const PENDING: u8 = 0;
    // const ACTIVE: u8 = 1;
    // const EXPIRED: u8 = 2;
    // const WITHDRAWN: u8 = 3;

    // With this enum
    enum StakeStatus has copy, drop, store {
        Pending,
        Active,
        Expired,
        Withdrawn
    }

    // Add this struct for daily revenue tracking
    struct DailyRevenueEntry has store, drop, copy {
        date: u64,              // UTC date
        amount: u64,            // Daily revenue amount
        distributed: bool,      // Whether this revenue has been distributed
        total_staked: u64,      // Total staked on that day
        staker_count: u64       // Number of stakers on that day
    }

    // Modify StakeEntry to track revenue by day
    struct StakeEntry has store, drop, copy {
        amount: u64,
        stake_date: u64,
        status: StakeStatus,  // This uses the enum
        activation_date: u64,
        expiry_date: u64,
        earned_from_revenue: vector<u64>,    // Vector of dates for which revenue was earned
        total_rewards: u64,
        daily_rewards: vector<DailyReward>,  // Track rewards by day
        reward_debt: u128,
        last_update: u64,
        withdrawn: bool,  // Add this field
        withdrawal_date: u64,  // Add this field
        restake_count: u64,  // Add this field to track number of restakes
        is_restaked: bool    // Add this to track if currently restaked
    }

    // Add this struct to track daily rewards
    struct DailyReward has store, drop, copy {
        date: u64,
        amount: u64
    }

    struct RevenueDeposit has store, drop, copy {
        amount: u64,
        deposit_time: u64
    }

    // Add new structs
    struct DailyLiquidityInfo has store, copy, drop {
        date: u64,
        total_staked: u64,
        staker_count: u64
    }

    struct LiquidityChangeEvent has store, drop {
        date: u64,
        amount: u64,
        is_addition: bool,  // true for stake, false for withdraw
        new_total: u64,
        timestamp: u64
    }

    // Update PoolInfo
    struct PoolInfo has key {
        owner_addr: address,
        withdraw_admin: address,
        staked_coins: Coin<Kryzel>,
        revenue_pool: Coin<Kryzel>,
        stakers: vector<address>,
        daily_revenues: vector<DailyRevenueEntry>,
        daily_stake_totals: vector<u64>,
        staker_count: u64,
        status_update_events: EventHandle<StatusUpdateEvent>,
        accumulated_rewards_per_share: u128,
        last_revenue_update: u64,
        previous_day_revenue: u64,
        restake_bonus_bps: u64,
        restake_events: EventHandle<RestakeEvent>,
        revenue1: u64,
        revenue2: u64,
        revenue_events: EventHandle<RevenueEvent>,
        reward_claim_events: EventHandle<RewardClaimEvent>,
        total_revenue: u64,
        total_staked: u64,
        withdraw_events: EventHandle<WithdrawEvent>,
        bulk_withdraw_events: EventHandle<BulkWithdrawEvent>,
        stake_events: EventHandle<StakeEvent>,
        liquidity_events: EventHandle<LiquidityChangeEvent>,
        daily_liquidity: vector<DailyLiquidityInfo>
    }

    struct UserStakes has key {
        stakes: vector<StakeEntry>
    }

    struct AdminCapability has key {
        sub_admins: vector<address>,
        owner: address,
        revenue_admins: vector<address>
    }

    struct RevenueEvent has store, drop {
        amount: u64,
        timestamp: u64,
        daily_total: u64,
        liquidity_pool: u64
    }

    struct RevenueInfo has key {
        total_revenue: u64,
        last_deposit_time: u64,
        daily_revenue: u64,          // Tracks today's revenue
        revenue_pool: coin::Coin<Kryzel>
    }

    struct RevenueSnapshot has store, drop, copy {
        timestamp: u64,
        revenue: u64,
        staker_count: u64,
        total_staked: u64
    }

    struct DailyStats has store, drop, copy {
        current_period_start: u64,
        daily_liquidity: u64,
        daily_revenue: u64,
        snapshots: vector<RevenueSnapshot>,
        utc_date: u64
    }

    struct HistoricalStats has key {
        // Daily stats for last 7 days (index 0 is today, 1 is yesterday, etc.)
        daily_stats: vector<DailyStat>,
        // Weekly aggregated stats
        weekly_stats: vector<WeeklyStat>,
        last_update: u64
    }

    struct DailyStat has store, drop, copy {
        date: u64,
        revenue: u64,          // Daily revenue only
        total_liquidity: u64   // Total staked amount only (LP)
    }

    struct WeeklyStat has store, drop, copy {
        week_start: u64,
        total_revenue: u64,
        total_liquidity: u64
    }

    // Simplified struct for stake view data
    struct StakeView has copy, drop {
        activation_date: u64,
        amount: u64,
        expiry_date: u64,
        last_update: u64,
        stake_date: u64,
        withdrawal_date: u64,
        withdrawn: bool,
        restake_count: u64,
        status: StakeStatus,
        user: address
    }

    // Simplified view struct for aggregated stats
    struct AggregatedStatsView has copy, drop {
        date: u64,              // Date (timestamp)
        total_liquidity: u64,   // Total KRZ in pool
        total_revenue: u64      // Aggregated revenue for all stakes
    }

    // Simplified struct for daily returns
    struct DailyReturnView has copy, drop {
        date: u64,              
        amount_staked: u64,     
        liquidity_pool: u64,    
        stake_count: u64        // Required field we forgot
    }

    // Keep old structs and add new ones
    struct DailyReturnViewV2 has copy, drop {
        date: u64,                  
        amount_staked: u64,         
        liquidity_pool: u64,        
        total_revenue: u64,         
        revenue_share: u64          
    }

    struct Stake has store {
        amount: u64,
        stake_date: u64,
        status: u8,
        restake_count: u64,    // Add this to track number of restakes
        total_rewards: u64     // Add this to track cumulative rewards
    }

    // Add these event structs
    struct StakeEvent has drop, store {
        user: address,
        amount: u64,
        stake_date: u64,
        activation_date: u64,
        expiry_date: u64,
        status: StakeStatus,
        last_update: u64,
        withdrawn: bool,
        withdrawal_date: u64,
        restake_count: u64
    }

    struct WithdrawEvent has store, drop {
        user: address,
        amount: u64,
        timestamp: u64
    }

    struct RestakeEvent has store, drop {
        user: address,
        amount: u64,
        timestamp: u64,
        new_activation_date: u64,    // Add new activation date
        new_expiry_date: u64,        // Add new expiry date
        restake_count: u64,          // Add restake count
        old_activation_date: u64,    // Add old activation date
        old_expiry_date: u64         // Add old expiry date
    }

    struct StatusUpdateEvent has store, drop {
        user: address,
        stake_id: u64,
        old_status: u8,
        new_status: u8,
        timestamp: u64
    }

    struct RewardClaimEvent has store, drop {
        user: address,
        amount: u64,
        timestamp: u64
    }

    // Add this struct
    struct StakerInfo has drop, copy {
        staker: address,
        stakes: vector<StakeView>
    }

    struct RevenueDay {
        date: u64,          // UTC date
        amount: u64,        // Revenue amount for this day
        distributed: bool   // Whether this revenue has been distributed
    }

    struct DailyRevenue has store, drop, copy {
        date: u64,
        amount: u64,
        staker_count: u64,
        total_staked: u64    // Add this to track total staked for that day
    }

    struct SubAdminCap has key {
        admin_addr: address
    }

    struct DailyStakeSummary has drop, copy {
        date: u64,
        stake_amount: u64,
        total_lp: u64,
        active_lp: u64,
        current_active_liquidity: u64,
        staker_count: u64,
        individual_stakes: vector<StakerInfo>
    }

    // Add new struct with different name
    struct UserDailySummary has store, drop {
        date: u64,
        user_stake_amount: u64,
        current_liquidity: u64,    // Historical total
        active_liquidity: u64      // Current active after withdrawals
    }

    struct WithdrawalInfo has drop {
        date: u64,
        amount: u64
    }

    // Add new event struct
    struct BulkWithdrawEvent has drop, store {
        processed_count: u64,
        total_amount: u64,
        timestamp: u64
    }

    // Helper function to get current UTC day number
    fun get_current_utc_day(): u64 {
        timestamp::now_seconds() / SECONDS_PER_DAY
    }

    // Helper function to get next UTC midnight
    fun get_next_utc_midnight(): u64 {
        let current_time = timestamp::now_seconds();
        let current_day = current_time / SECONDS_PER_DAY;
        (current_day + 1) * SECONDS_PER_DAY  // Next UTC midnight
    }

    public entry fun initialize(deployer: &signer) {
        let deployer_addr = signer::address_of(deployer);
        
        // Initialize AdminCapability
        if (!exists<AdminCapability>(@test_addr)) {
            move_to(deployer, AdminCapability {
                owner: deployer_addr,
                revenue_admins: vector::empty(),
                sub_admins: vector::empty()
            });
        };
        
        // Initialize PoolInfo
        if (!exists<PoolInfo>(@test_addr)) {
            move_to(deployer, PoolInfo {
                owner_addr: deployer_addr,
                stakers: vector::empty(),
                total_staked: 0,
                staked_coins: coin::zero<Kryzel>(),
                accumulated_rewards_per_share: 0,
                daily_revenues: vector::empty(),
                daily_stake_totals: vector::empty(),
                last_revenue_update: 0,
                previous_day_revenue: 0,
                restake_bonus_bps: 0,
                restake_events: account::new_event_handle<RestakeEvent>(deployer),
                revenue1: 0,
                revenue2: 0,
                revenue_events: account::new_event_handle<RevenueEvent>(deployer),
                revenue_pool: coin::zero<Kryzel>(),
                reward_claim_events: account::new_event_handle<RewardClaimEvent>(deployer),
                staker_count: 0,
                status_update_events: account::new_event_handle<StatusUpdateEvent>(deployer),
                total_revenue: 0,
                withdraw_admin: deployer_addr,
                withdraw_events: account::new_event_handle<WithdrawEvent>(deployer),
                bulk_withdraw_events: account::new_event_handle<BulkWithdrawEvent>(deployer),
                stake_events: account::new_event_handle<StakeEvent>(deployer),
                liquidity_events: account::new_event_handle<LiquidityChangeEvent>(deployer),
                daily_liquidity: vector::empty<DailyLiquidityInfo>(),
            });
        };
    }

    public entry fun stake(account: &signer, amount: u64) acquires PoolInfo, UserStakes {
        let current_time = timestamp::now_seconds();
        let current_day = current_time / SECONDS_PER_DAY;
        let next_midnight = (current_day + 1) * SECONDS_PER_DAY;
        
        let user_addr = signer::address_of(account);
        let pool_info = borrow_global_mut<PoolInfo>(@test_addr);
        
        // Add staker to the list if not already present
        if (!vector::contains(&pool_info.stakers, &user_addr)) {
            vector::push_back(&mut pool_info.stakers, user_addr);
        };
        
        // Transfer tokens from user to pool
        let coins = coin::withdraw<Kryzel>(account, amount);
        coin::merge(&mut pool_info.staked_coins, coins);
        
        // Initialize UserStakes if not exists
        if (!exists<UserStakes>(user_addr)) {
            move_to(account, UserStakes {
                stakes: vector::empty()
            });
        };
        
        let user_stakes = borrow_global_mut<UserStakes>(user_addr);
        
        let stake_entry = StakeEntry {
            amount,
            stake_date: current_time,
            status: StakeStatus::Pending,
            activation_date: next_midnight,
            expiry_date: next_midnight + (2 * SECONDS_PER_DAY),
            earned_from_revenue: vector::empty(),
            total_rewards: 0,
            daily_rewards: vector::empty(),
            reward_debt: 0,
            last_update: current_time,
            withdrawn: false,
            withdrawal_date: 0,
            restake_count: 0,
            is_restaked: false
        };
        
        vector::push_back(&mut user_stakes.stakes, stake_entry);

        // Emit stake event with all fields
        event::emit_event(
            &mut pool_info.stake_events,
            StakeEvent {
                user: user_addr,
                amount,
                stake_date: current_time,
                activation_date: next_midnight,
                expiry_date: next_midnight + (2 * SECONDS_PER_DAY),
                status: StakeStatus::Pending,
                last_update: current_time,
                withdrawn: false,
                withdrawal_date: 0,
                restake_count: 0
            }
        );
    }

    public entry fun withdraw(user: &signer, amount: u64) acquires PoolInfo {
        let pool_info = borrow_global_mut<PoolInfo>(@test_addr);
        assert!(coin::value<Kryzel>(&pool_info.staked_coins) >= amount, EINSUFFICIENT_BALANCE);
        let withdraw_coins = coin::extract<Kryzel>(&mut pool_info.staked_coins, amount);
        coin::deposit(signer::address_of(user), withdraw_coins);
    }

    public entry fun restake(account: &signer, stake_index: u64) acquires UserStakes, PoolInfo {
        let current_time = timestamp::now_seconds();
        let current_day = current_time / SECONDS_PER_DAY;
        let user_addr = signer::address_of(account);
        let user_stakes = borrow_global_mut<UserStakes>(user_addr);
        let pool_info = borrow_global_mut<PoolInfo>(@test_addr);
        let stake = vector::borrow_mut(&mut user_stakes.stakes, stake_index);
        
        // Calculate which day of activation we're in
        let activation_day = stake.activation_date / SECONDS_PER_DAY;
        let days_since_activation = current_day - activation_day;
        
        // Can only restake on second day of activation
        assert!(days_since_activation == 1, EINVALID_STATUS); // Must be second day
        assert!(!stake.withdrawn, EINVALID_STATUS);
        
        // Store old dates for event
        let old_activation_date = stake.activation_date;
        let old_expiry_date = stake.expiry_date;
        
        // Update stake timeline (but preserve original stake_date)
        stake.activation_date = ((current_time / SECONDS_PER_DAY) + 1) * SECONDS_PER_DAY;  // Next UTC midnight
        stake.expiry_date = stake.activation_date + (2 * SECONDS_PER_DAY);                 // 2 days after activation
        stake.restake_count = stake.restake_count + 1;

        // Emit enhanced restake event
        event::emit_event(
            &mut pool_info.restake_events,
            RestakeEvent {
                user: user_addr,
                amount: stake.amount,
                timestamp: current_time,
                new_activation_date: stake.activation_date,
                new_expiry_date: stake.expiry_date,
                restake_count: stake.restake_count,
                old_activation_date,
                old_expiry_date
            }
        );
    }

    // Add sub-admin
    public entry fun add_sub_admin(
        admin: &signer,
        sub_admin_addr: address
    ) acquires PoolInfo {
        let admin_addr = signer::address_of(admin);
        let pool_info = borrow_global<PoolInfo>(@test_addr);
        
        // Only main admin can add sub-admins
        assert!(admin_addr == pool_info.owner_addr, EINVALID_OWNER);
        
        // Create and move SubAdminCap to the sub-admin's address
        move_to(admin, SubAdminCap {
            admin_addr: sub_admin_addr
        });
    }

    // Function for main admin to remove sub-admin
    public entry fun remove_sub_admin(
        admin: &signer,
        sub_admin_addr: address
    ) acquires PoolInfo, SubAdminCap {
        let admin_addr = signer::address_of(admin);
        let pool_info = borrow_global<PoolInfo>(@test_addr);
        
        // Only main admin can remove sub-admins
        assert!(admin_addr == pool_info.owner_addr, EINVALID_OWNER);
        
        // Remove SubAdminCap if it exists
        if (exists<SubAdminCap>(sub_admin_addr)) {
            let SubAdminCap { admin_addr: _ } = move_from<SubAdminCap>(sub_admin_addr);
        };
    }

    // Admin withdraw function
    public entry fun admin_withdraw(
        admin: &signer,
        user_addr: address,
        stake_index: u64
    ) acquires PoolInfo, UserStakes {
        let admin_addr = signer::address_of(admin);
        let pool_info = borrow_global_mut<PoolInfo>(@test_addr);
        assert!(admin_addr == pool_info.owner_addr, EINVALID_OWNER);
        
        // Check if stake is expired
        let user_stakes = borrow_global<UserStakes>(user_addr);
        let stake = vector::borrow(&user_stakes.stakes, stake_index);
        assert!(stake.status == StakeStatus::Expired, EINVALID_STATUS);
        
        // Process withdrawal
        let withdraw_amount = stake.amount;
        
        // Transfer tokens back to user
        let withdraw_coins = coin::extract<Kryzel>(&mut pool_info.staked_coins, withdraw_amount);
        coin::deposit(user_addr, withdraw_coins);
        
        // Remove stake entry
        let user_stakes = borrow_global_mut<UserStakes>(user_addr);
        vector::remove(&mut user_stakes.stakes, stake_index);
    }

    // Simplified function to get user's stake details
    #[view]
    public fun get_user_stakes(user_addr: address): vector<StakeView> acquires UserStakes {
        let stakes = vector::empty<StakeView>();
        if (!exists<UserStakes>(user_addr)) {
            return stakes
        };
        
        let user_stakes = borrow_global<UserStakes>(user_addr);
        let current_time = timestamp::now_seconds();
        
        let i = 0;
        let len = vector::length(&user_stakes.stakes);
        
        while (i < len) {
            let stake = vector::borrow(&user_stakes.stakes, i);
            
            // Determine current status based on time
            let current_status = if (stake.withdrawn) {
                StakeStatus::Withdrawn
            } else if (current_time >= stake.expiry_date) {
                StakeStatus::Expired
            } else if (current_time >= stake.activation_date) {
                StakeStatus::Active
            } else {
                StakeStatus::Pending
            };

            let view = StakeView {
                activation_date: stake.activation_date,
                amount: stake.amount,
                expiry_date: stake.expiry_date,
                last_update: stake.last_update,
                stake_date: stake.stake_date,
                withdrawal_date: stake.withdrawal_date,
                withdrawn: stake.withdrawn,
                restake_count: stake.restake_count,
                status: current_status,
                user: user_addr
            };
            vector::push_back(&mut stakes, view);
            i = i + 1;
        };
        
        stakes
    }

    // Get all stakes across all users
    #[view]
    public fun get_all_stakes(user_addr: address): (vector<StakeEntry>, u64) acquires UserStakes, PoolInfo {
        let stakes = if (!exists<UserStakes>(user_addr)) {
            vector::empty<StakeEntry>()
        } else {
            let user_stakes = borrow_global<UserStakes>(user_addr);
            *&user_stakes.stakes
        };
        
        let pool_info = borrow_global<PoolInfo>(@test_addr);
        let total_staked = pool_info.total_staked;
        
        (stakes, total_staked)
    }

    fun get_all_stakers(): vector<address> acquires PoolInfo {
        let pool_info = borrow_global<PoolInfo>(@test_addr);
        pool_info.stakers
    }

    #[view]
    public fun get_current_timestamp(): u64 {
        timestamp::now_seconds()
    }

    // Also add a view function for total staked
    #[view]
    public fun get_total_staked(): u64 acquires PoolInfo {
        let pool_info = borrow_global<PoolInfo>(@test_addr);
        pool_info.total_staked
    }

    #[view]
    public fun get_user_daily_summary(user_addr: address): vector<UserDailySummary> acquires UserStakes, PoolInfo {
        let result = vector::empty<UserDailySummary>();
        
        if (!exists<UserStakes>(user_addr)) {
            return result
        };
        
        let pool_info = borrow_global<PoolInfo>(@test_addr);
        let dates = vector::empty<u64>();
        let stakers = *&pool_info.stakers;
        
        // First collect all dates and withdrawals
        let i = 0;
        let withdrawals = vector::empty<WithdrawalInfo>();
        
        while (i < vector::length(&stakers)) {
            let staker = *vector::borrow(&stakers, i);
            if (exists<UserStakes>(staker)) {
                let user_stakes = borrow_global<UserStakes>(staker);
                let j = 0;
                while (j < vector::length(&user_stakes.stakes)) {
                    let stake = vector::borrow(&user_stakes.stakes, j);
                    if (!vector::contains(&dates, &stake.stake_date)) {
                        vector::push_back(&mut dates, stake.stake_date);
                    };
                    // Track withdrawals
                    if (stake.withdrawn) {
                        vector::push_back(&mut withdrawals, WithdrawalInfo {
                            date: stake.withdrawal_date,
                            amount: stake.amount
                        });
                    };
                    j = j + 1;
                };
            };
            i = i + 1;
        };
        
        // Sort dates
        sort_dates(&mut dates);
        
        // Calculate running total for each date
        i = 0;
        let running_total = 0u64;
        let withdrawn_total = 0u64;
        
        while (i < vector::length(&dates)) {
            let current_date = *vector::borrow(&dates, i);
            
            // Add new stakes for this date
            let daily_stakes = 0u64;
            let j = 0;
            while (j < vector::length(&stakers)) {
                let staker = *vector::borrow(&stakers, j);
                if (exists<UserStakes>(staker)) {
                    let user_stakes = borrow_global<UserStakes>(staker);
                    let k = 0;
                    while (k < vector::length(&user_stakes.stakes)) {
                        let stake = vector::borrow(&user_stakes.stakes, k);
                        if (stake.stake_date == current_date) {
                            daily_stakes = daily_stakes + stake.amount;
                        };
                        k = k + 1;
                    };
                };
                j = j + 1;
            };
            
            running_total = running_total + daily_stakes;
            
            // Process withdrawals up to this date
            let j = 0;
            while (j < vector::length(&withdrawals)) {
                let withdrawal = vector::borrow(&withdrawals, j);
                if (withdrawal.date <= current_date && withdrawal.date > *vector::borrow(&dates, if (i == 0) 0 else i - 1)) {
                    withdrawn_total = withdrawn_total + withdrawal.amount;
                };
                j = j + 1;
            };
            
            // Add entry for user if they have stake on this date
            let user_stakes = borrow_global<UserStakes>(user_addr);
            let k = 0;
            while (k < vector::length(&user_stakes.stakes)) {
                let stake = vector::borrow(&user_stakes.stakes, k);
                if (stake.stake_date == current_date) {
                    vector::push_back(&mut result, UserDailySummary {
                        date: current_date,
                        user_stake_amount: stake.amount,
                        current_liquidity: stake.amount,
                        active_liquidity: if (i == 0) running_total 
                                        else running_total - withdrawn_total
                    });
                };
                k = k + 1;
            };
            
            i = i + 1;
        };
        
        result
    }

    #[view]
    public fun get_all_stakes_with_daily_totals(): vector<DailyStakeSummary> acquires PoolInfo, UserStakes {
        let pool_info = borrow_global<PoolInfo>(@test_addr);
        let result = vector::empty<DailyStakeSummary>();
        let dates = vector::empty<u64>();
        let stakers = *&pool_info.stakers;
        
        // First calculate current active liquidity across all stakes
        let current_active_liquidity = 0u64;
        let i = 0;
        while (i < vector::length(&stakers)) {
            let staker = *vector::borrow(&stakers, i);
            if (exists<UserStakes>(staker)) {
                let user_stakes = borrow_global<UserStakes>(staker);
                let j = 0;
                while (j < vector::length(&user_stakes.stakes)) {
                    let stake = vector::borrow(&user_stakes.stakes, j);
                    if (!stake.withdrawn) {
                        current_active_liquidity = current_active_liquidity + stake.amount;
                    };
                    j = j + 1;
                };
            };
            i = i + 1;
        };
        
        // First collect all dates
        let i = 0;
        while (i < vector::length(&stakers)) {
            let staker = *vector::borrow(&stakers, i);
            if (exists<UserStakes>(staker)) {
                let user_stakes = borrow_global<UserStakes>(staker);
                let j = 0;
                while (j < vector::length(&user_stakes.stakes)) {
                    let stake = vector::borrow(&user_stakes.stakes, j);
                    if (!vector::contains(&dates, &stake.stake_date)) {
                        vector::push_back(&mut dates, stake.stake_date);
                    };
                    j = j + 1;
                };
            };
            i = i + 1;
        };
        
        sort_dates(&mut dates);
        
        // Process each date
        let historical_total = 0u64;
        i = 0;
        let dates_len = vector::length(&dates);
        while (i < dates_len) {
            let current_date = *vector::borrow(&dates, i);
            let daily_stake_amount = 0u64;
            let staker_count = 0u64;
            let daily_stakes = vector::empty<StakerInfo>();
            let active_total = 0u64;
            
            // Process all stakers for this date
            let j = 0;
            while (j < vector::length(&stakers)) {
                let staker = *vector::borrow(&stakers, j);
                if (exists<UserStakes>(staker)) {
                    let user_stakes = borrow_global<UserStakes>(staker);
                    let has_stake_this_day = false;
                    let stakes_this_day = vector::empty<StakeView>();
                    
                    // Process all stakes for this staker
                    let k = 0;
                    while (k < vector::length(&user_stakes.stakes)) {
                        let stake = vector::borrow(&user_stakes.stakes, k);
                        
                        // If stake is from this date, add to daily totals
                        if (stake.stake_date == current_date) {
                            daily_stake_amount = daily_stake_amount + stake.amount;
                            has_stake_this_day = true;
                            let current_time = timestamp::now_seconds();
                            let view = StakeView {
                                activation_date: stake.activation_date,
                                amount: stake.amount,
                                expiry_date: stake.expiry_date,
                                last_update: stake.last_update,
                                stake_date: stake.stake_date,
                                withdrawal_date: stake.withdrawal_date,
                                withdrawn: stake.withdrawn,
                                restake_count: stake.restake_count,
                                status: if (stake.withdrawn) {
                                    StakeStatus::Withdrawn
                                } else if (current_time >= stake.expiry_date) {
                                    StakeStatus::Expired
                                } else if (current_time >= stake.activation_date) {
                                    StakeStatus::Active
                                } else {
                                    StakeStatus::Pending
                                },
                                user: staker
                            };
                            vector::push_back(&mut stakes_this_day, view);
                        };
                        
                        // If stake is not withdrawn, add to active total
                        if (!stake.withdrawn && stake.stake_date <= current_date) {
                            active_total = active_total + stake.amount;
                        };
                        
                        k = k + 1;
                    };
                    
                    if (has_stake_this_day) {
                        staker_count = staker_count + 1;
                        vector::push_back(&mut daily_stakes, StakerInfo { staker, stakes: stakes_this_day });
                    };
                };
                j = j + 1;
            };
            
            historical_total = historical_total + daily_stake_amount;
            
            vector::push_back(&mut result, DailyStakeSummary {
                date: current_date,
                stake_amount: daily_stake_amount,
                total_lp: historical_total,
                active_lp: active_total,
                current_active_liquidity,
                staker_count,
                individual_stakes: daily_stakes
            });
            
            i = i + 1;
        };
        
        result
    }

    // Helper function to sort dates
    fun sort_dates(dates: &mut vector<u64>) {
        let i = 0;
        let len = vector::length(dates);
        while (i < len) {
            let j = i + 1;
            while (j < len) {
                let date_i = *vector::borrow(dates, i);
                let date_j = *vector::borrow(dates, j);
                if (date_j < date_i) {
                    vector::swap(dates, i, j);
                };
                j = j + 1;
            };
            i = i + 1;
        };
    }

    // View function to check all stakes status
    #[view]
    public fun check_stake_status(user_addr: address): vector<StakeStatus> acquires UserStakes {
        if (!exists<UserStakes>(user_addr)) {
            return vector::empty<StakeStatus>()
        };
        
        let user_stakes = borrow_global<UserStakes>(user_addr);
        let result = vector::empty<StakeStatus>();
        
        let i = 0;
        let len = vector::length(&user_stakes.stakes);
        
        while (i < len) {
            let stake = vector::borrow(&user_stakes.stakes, i);
            vector::push_back(&mut result, stake.status);
            i = i + 1;
        };
        
        result
    }



    #[view]
    public fun get_liquidity_pool_info(): (u64, u64, u64) acquires PoolInfo {
        let pool_info = borrow_global<PoolInfo>(@test_addr);
        (
            coin::value(&pool_info.staked_coins),      // Total staked tokens
            coin::value(&pool_info.revenue_pool),      // Total revenue tokens
            pool_info.staker_count                     // Number of stakers
        )
    }

    #[view]
    public fun get_daily_liquidity(): vector<DailyLiquidityInfo> acquires PoolInfo {
        let pool_info = borrow_global<PoolInfo>(@test_addr);
        *&pool_info.daily_liquidity
    }

    // User withdraw expired stake function
    public entry fun withdraw_stake(user: &signer, stake_index: u64) acquires PoolInfo, UserStakes {
        let user_addr = signer::address_of(user);
        let pool_info = borrow_global_mut<PoolInfo>(@test_addr);
        let user_stakes = borrow_global_mut<UserStakes>(user_addr);
        
        let stake = vector::borrow(&user_stakes.stakes, stake_index);
        assert!(stake.status == StakeStatus::Expired, EINVALID_STATUS);
        
        let withdraw_amount = stake.amount;
        
        // Update total staked
        pool_info.total_staked = pool_info.total_staked - withdraw_amount;
        
        // Process withdrawal
        let withdraw_coins = coin::extract<Kryzel>(&mut pool_info.staked_coins, withdraw_amount);
        coin::deposit(user_addr, withdraw_coins);
        
        // Emit withdraw event
        event::emit_event(
            &mut pool_info.withdraw_events,
            WithdrawEvent {
                user: user_addr,
                amount: withdraw_amount,
                timestamp: timestamp::now_seconds()
            }
        );
    }

    // Keep original signature for process_withdraw_batch
    public entry fun process_withdraw_batch(
        admin: &signer,
        users: vector<address>  // Keep original vector parameter
    ) acquires PoolInfo, UserStakes, AdminCapability {
        let admin_addr = signer::address_of(admin);
        let caps = borrow_global<AdminCapability>(@test_addr);
        assert!(admin_addr == caps.owner, EINVALID_OWNER);
        
        let current_time = timestamp::now_seconds();
        let pool_info = borrow_global_mut<PoolInfo>(@test_addr);
        
        let processed_count = 0u64;
        let total_withdrawn = 0u64;
        
        let i = 0;
        while (i < vector::length(&users)) {
            let user_addr = *vector::borrow(&users, i);
            if (exists<UserStakes>(user_addr)) {
                let user_stakes = borrow_global_mut<UserStakes>(user_addr);
                let j = 0;
                while (j < vector::length(&user_stakes.stakes)) {
                    let stake = vector::borrow_mut(&mut user_stakes.stakes, j);
                    if (!stake.withdrawn && current_time >= stake.expiry_date) {
                        // Process withdrawal for expired stake
                        let withdraw_amount = stake.amount;
                        
                        assert!(pool_info.total_staked >= withdraw_amount, EINSUFFICIENT_BALANCE);
                        
                        pool_info.total_staked = pool_info.total_staked - withdraw_amount;
                        
                        let withdraw_coins = coin::extract<Kryzel>(&mut pool_info.staked_coins, withdraw_amount);
                        coin::deposit(user_addr, withdraw_coins);
                        
                        // Mark as withdrawn
                        stake.withdrawn = true;
                        stake.withdrawal_date = current_time;
                        
                        // Update counters
                        processed_count = processed_count + 1;
                        total_withdrawn = total_withdrawn + withdraw_amount;
                        
                        // Emit individual withdraw event
                        event::emit_event(
                            &mut pool_info.withdraw_events,
                            WithdrawEvent {
                                user: user_addr,
                                amount: withdraw_amount,
                                timestamp: current_time
                            }
                        );

                        // Emit liquidity event for withdrawal
                        event::emit_event(
                            &mut pool_info.liquidity_events,
                            LiquidityChangeEvent {
                                date: current_time / SECONDS_PER_DAY,
                                amount: withdraw_amount,
                                is_addition: false,
                                new_total: pool_info.total_staked,
                                timestamp: current_time
                            }
                        );
                    };
                    j = j + 1;
                };
            };
            i = i + 1;
        };
        
        // Only emit bulk withdraw event if something was processed
        if (processed_count > 0) {
            event::emit_event(
                &mut pool_info.bulk_withdraw_events,
                BulkWithdrawEvent {
                    processed_count,
                    total_amount: total_withdrawn,
                    timestamp: current_time
                }
            );
        };
    }

    // Fix process_withdraw_admin by removing assertion
    public entry fun process_withdraw_admin(admin: &signer) acquires PoolInfo, UserStakes, AdminCapability {
        let admin_addr = signer::address_of(admin);
        let caps = borrow_global<AdminCapability>(@test_addr);
        assert!(admin_addr == caps.owner, EINVALID_OWNER);
        
        let current_time = timestamp::now_seconds();
        let pool_info = borrow_global_mut<PoolInfo>(@test_addr);
        let stakers = *&pool_info.stakers;
        
        let processed_count = 0u64;
        let total_withdrawn = 0u64;
        
        let i = 0;
        while (i < vector::length(&stakers)) {
            let staker = *vector::borrow(&stakers, i);
            if (exists<UserStakes>(staker)) {
                let user_stakes = borrow_global_mut<UserStakes>(staker);
                let j = 0;
                while (j < vector::length(&user_stakes.stakes)) {
                    let stake = vector::borrow_mut(&mut user_stakes.stakes, j);
                    if (!stake.withdrawn && current_time >= stake.expiry_date) {
                        // Process withdrawal for expired stake
                        let withdraw_amount = stake.amount;
                        
                        assert!(pool_info.total_staked >= withdraw_amount, EINSUFFICIENT_BALANCE);
                        
                        pool_info.total_staked = pool_info.total_staked - withdraw_amount;
                        
                        let withdraw_coins = coin::extract<Kryzel>(&mut pool_info.staked_coins, withdraw_amount);
                        coin::deposit(staker, withdraw_coins);
                        
                        // Mark as withdrawn
                        stake.withdrawn = true;
                        stake.withdrawal_date = current_time;
                        
                        // Update counters
                        processed_count = processed_count + 1;
                        total_withdrawn = total_withdrawn + withdraw_amount;
                        
                        // Emit individual withdraw event
                        event::emit_event(
                            &mut pool_info.withdraw_events,
                            WithdrawEvent {
                                user: staker,
                                amount: withdraw_amount,
                                timestamp: current_time
                            }
                        );

                        // Emit liquidity event for withdrawal
                        event::emit_event(
                            &mut pool_info.liquidity_events,
                            LiquidityChangeEvent {
                                date: current_time / SECONDS_PER_DAY,
                                amount: withdraw_amount,
                                is_addition: false,
                                new_total: pool_info.total_staked,
                                timestamp: current_time
                            }
                        );
                    };
                    j = j + 1;
                };
            };
            i = i + 1;
        };
        
        // Only emit bulk withdraw event if something was processed
        if (processed_count > 0) {
            event::emit_event(
                &mut pool_info.bulk_withdraw_events,
                BulkWithdrawEvent {
                    processed_count,
                    total_amount: total_withdrawn,
                    timestamp: current_time
                }
            );
        };
    }

    #[view]
    public fun get_daily_returns(): vector<DailyReturnView> acquires UserStakes, PoolInfo {
        let pool_info = borrow_global<PoolInfo>(@test_addr);
        let returns = vector::empty<DailyReturnView>();
        let stakers = *&pool_info.stakers;
        
        // First collect all transaction dates (stakes and withdrawals)
        let dates = vector::empty<u64>();
        let i = 0;
        
        // Collect stake dates
        while (i < vector::length(&stakers)) {
            let staker = *vector::borrow(&stakers, i);
            if (exists<UserStakes>(staker)) {
                let user_stakes = borrow_global<UserStakes>(staker);
                let j = 0;
                while (j < vector::length(&user_stakes.stakes)) {
                    let stake = vector::borrow(&user_stakes.stakes, j);
                    // Add stake dates
                    if (!vector::contains(&dates, &stake.stake_date)) {
                        vector::push_back(&mut dates, stake.stake_date);
                    };
                    // Add withdrawal dates
                    if (stake.withdrawn && !vector::contains(&dates, &stake.withdrawal_date)) {
                        vector::push_back(&mut dates, stake.withdrawal_date);
                    };
                    j = j + 1;
                };
            };
            i = i + 1;
        };

        // Sort dates chronologically
        sort_dates(&mut dates);

        // Process each date like a bank ledger
        let running_total = 0u64;
        i = 0;
        while (i < vector::length(&dates)) {
            let current_date = *vector::borrow(&dates, i);
            let daily_stake_amount = 0u64;
            let daily_withdrawal_amount = 0u64;
            
            // Calculate stakes and withdrawals for this date
            let j = 0;
            while (j < vector::length(&stakers)) {
                let staker = *vector::borrow(&stakers, j);
                if (exists<UserStakes>(staker)) {
                    let user_stakes = borrow_global<UserStakes>(staker);
                    let k = 0;
                    while (k < vector::length(&user_stakes.stakes)) {
                        let stake = vector::borrow(&user_stakes.stakes, k);
                        // Add new stakes
                        if (stake.stake_date == current_date) {
                            daily_stake_amount = daily_stake_amount + stake.amount;
                            running_total = running_total + stake.amount;
                        };
                        // Subtract withdrawals
                        if (stake.withdrawn && stake.withdrawal_date == current_date) {
                            daily_withdrawal_amount = daily_withdrawal_amount + stake.amount;
                            running_total = running_total - stake.amount;
                        };
                        k = k + 1;
                    };
                };
                j = j + 1;
            };

            // Only create entry if there was activity (stakes or withdrawals)
            if (daily_stake_amount > 0 || daily_withdrawal_amount > 0) {
                let view = DailyReturnView {
                    date: current_date,
                    amount_staked: daily_stake_amount,     // New stakes that day
                    liquidity_pool: running_total,         // Actual historical balance
                    stake_count: if (daily_stake_amount > 0) 1 else 0  // Count of stakes that day
                };
                vector::push_back(&mut returns, view);
            };
            i = i + 1;
        };

        returns
    }

    // Helper function to sort stakes by date
    fun sort_by_date(stakes: &mut vector<StakeEntry>) {
        let i = 0;
        let len = vector::length(stakes);
        while (i < len) {
            let j = i + 1;
            while (j < len) {
                let stake_i = vector::borrow(stakes, i);
                let stake_j = vector::borrow(stakes, j);
                if (stake_j.stake_date < stake_i.stake_date) {
                    vector::swap(stakes, i, j);
                };
                j = j + 1;
            };
            i = i + 1;
        };
    }

    // Function to update stake statuses
    public entry fun update_stake_statuses() acquires PoolInfo, UserStakes {
        let current_time = timestamp::now_seconds();
        let current_day = get_current_utc_day();
        
        let pool_info = borrow_global_mut<PoolInfo>(@test_addr);
        let stakers = *&pool_info.stakers;
        
        let i = 0;
        while (i < vector::length(&stakers)) {
            let staker = *vector::borrow(&stakers, i);
            if (exists<UserStakes>(staker)) {
                let user_stakes = borrow_global_mut<UserStakes>(staker);
                let j = 0;
                while (j < vector::length(&user_stakes.stakes)) {
                    let stake = vector::borrow_mut(&mut user_stakes.stakes, j);
                    
                    if (!stake.withdrawn) {
                        // Calculate days since stake
                        let stake_day = stake.stake_date / SECONDS_PER_DAY;
                        let days_since_stake = current_day - stake_day;
                        
                        // Update status based on days using enum
                        if (days_since_stake == 0) {
                            stake.status = StakeStatus::Pending;      // Day 1: In Process
                        } else if (days_since_stake == 1 || days_since_stake == 2) {
                            stake.status = StakeStatus::Active;       // Day 2-3: Active, can restake
                        } else if (days_since_stake >= 3) {
                            stake.status = StakeStatus::Expired;      // Day 4+: Expired
                        };
                    };
                    j = j + 1;
                };
            };
            i = i + 1;
        };
    }

    #[view]
    public fun get_pool_info(): (u64, u64) acquires PoolInfo {
        let pool_info = borrow_global<PoolInfo>(@test_addr);
        let total_staked = coin::value<Kryzel>(&pool_info.staked_coins);
        (total_staked, pool_info.total_revenue)
    }

    #[view]
    public fun get_pool_details(): (u64, vector<address>) acquires PoolInfo {
        let pool_info = borrow_global<PoolInfo>(@test_addr);
        (pool_info.total_staked, *&pool_info.stakers)
    }

    #[view]
    public fun get_stakers_list(): vector<address> acquires PoolInfo {
        let pool_info = borrow_global<PoolInfo>(@test_addr);
        *&pool_info.stakers
    }

    public entry fun rebuild_stakers_list(admin: &signer) acquires PoolInfo, AdminCapability {
        let admin_addr = signer::address_of(admin);
        let caps = borrow_global<AdminCapability>(@test_addr);
        assert!(admin_addr == caps.owner, EINVALID_OWNER);
        
        let pool_info = borrow_global_mut<PoolInfo>(@test_addr);

        // Clear existing stakers list
        pool_info.stakers = vector::empty();

        // Add all known stakers
        let stakers = vector[@0x69d738995c2d7ee9b59c87a6b4ba578ebb6848c9d8de4f47f9ea9512584f4de3,
                    @0x53ca3c984da3a5b57c9e63eb914f3d0325eccd36ab9ed2e2fb9f08fdf36bef5e,
                    @0xdd80333f63bca1e9ba8aad19d2dbf1f315471ac7ee19208dad205b1c7dc3a801];

        let i = 0;
        while (i < vector::length(&stakers)) {
            let staker = *vector::borrow(&stakers, i);
            if (exists<UserStakes>(staker) && !vector::contains(&pool_info.stakers, &staker)) {
                vector::push_back(&mut pool_info.stakers, staker);
            };
            i = i + 1;
        };
    }

    #[view]
    public fun get_expired_stakes(): vector<StakeView> acquires PoolInfo, UserStakes {
        let pool_info = borrow_global<PoolInfo>(@test_addr);
        let stakers = *&pool_info.stakers;
        let expired_stakes = vector::empty<StakeView>();
        let current_time = timestamp::now_seconds();
        
        let i = 0;
        while (i < vector::length(&stakers)) {
            let staker = *vector::borrow(&stakers, i);
            if (exists<UserStakes>(staker)) {
                let user_stakes = borrow_global<UserStakes>(staker);
                let j = 0;
                while (j < vector::length(&user_stakes.stakes)) {
                    let stake = vector::borrow(&user_stakes.stakes, j);
                    if (!stake.withdrawn && current_time >= stake.expiry_date) {
                        vector::push_back(&mut expired_stakes, StakeView {
                            activation_date: stake.activation_date,
                            amount: stake.amount,
                            expiry_date: stake.expiry_date,
                            last_update: stake.last_update,
                            stake_date: stake.stake_date,
                            withdrawal_date: stake.withdrawal_date,
                            withdrawn: stake.withdrawn,
                            restake_count: stake.restake_count,
                            status: stake.status,
                            user: staker
                        });
                    };
                    j = j + 1;
                };
            };
            i = i + 1;
        };
        
        expired_stakes
    }

    // Simplified version - only checks expiry time and withdrawn status
    public entry fun process_expired_withdrawals(admin: &signer) acquires PoolInfo, UserStakes, AdminCapability {
        let admin_addr = signer::address_of(admin);
        let caps = borrow_global<AdminCapability>(@test_addr);
        assert!(admin_addr == caps.owner, EINVALID_OWNER);
        
        let current_time = timestamp::now_seconds();
        let pool_info = borrow_global_mut<PoolInfo>(@test_addr);
        let stakers = *&pool_info.stakers;
        
        let processed_count = 0u64;
        let total_withdrawn = 0u64;
        
        let i = 0;
        while (i < vector::length(&stakers)) {
            let staker = *vector::borrow(&stakers, i);
            if (exists<UserStakes>(staker)) {
                let user_stakes = borrow_global_mut<UserStakes>(staker);
                let j = 0;
                while (j < vector::length(&user_stakes.stakes)) {
                    let stake = vector::borrow_mut(&mut user_stakes.stakes, j);
                    // Only check expiry time and not withdrawn
                    if (current_time >= stake.expiry_date && !stake.withdrawn) {
                        let withdraw_amount = stake.amount;
                        let withdraw_coins = coin::extract<Kryzel>(&mut pool_info.staked_coins, withdraw_amount);
                        coin::deposit(staker, withdraw_coins);
                        
                        stake.withdrawn = true;
                        stake.withdrawal_date = current_time;
                        
                        processed_count = processed_count + 1;
                        total_withdrawn = total_withdrawn + withdraw_amount;
                        
                        event::emit_event(
                            &mut pool_info.withdraw_events,
                            WithdrawEvent {
                                user: staker,
                                amount: withdraw_amount,
                                timestamp: current_time
                            }
                        );
                    };
                    j = j + 1;
                };
            };
            i = i + 1;
        };
        
        if (processed_count > 0) {
            event::emit_event(
                &mut pool_info.bulk_withdraw_events,
                BulkWithdrawEvent {
                    processed_count,
                    total_amount: total_withdrawn,
                    timestamp: current_time
                }
            );
        };
    }

    // Update all places where we create StakeView
    public fun get_stake_view(stake: &StakeEntry, user: address): StakeView {
        StakeView {
            activation_date: stake.activation_date,
            amount: stake.amount,
            expiry_date: stake.expiry_date,
            last_update: stake.last_update,
            stake_date: stake.stake_date,
            withdrawal_date: stake.withdrawal_date,
            withdrawn: stake.withdrawn,
            restake_count: stake.restake_count,
            status: stake.status,
            user
        }
    }
} 

