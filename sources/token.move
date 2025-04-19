module iota_test::testi_token {
    use iota::coin_manager::{Self, CoinManager, CoinManagerTreasuryCap};
    use iota::table::{Self, Table};
    use iota::event::Self;

    const EClaim: u64 = 0;

    const MAX_SUPPLY: u64 = 100000000;
    const INITIAL_SUPPLY: u64 = 1000;
    const CLAIMABLE: u64 = 100;

    public struct TESTI_TOKEN has drop {}
    public struct TestEventSharedObj has copy, drop { addr_obj: address }

    public struct TestEventTransfer has copy, drop {
        from: address,
        to: address,
        amount: u64
    }

    public struct ClaimTracker has key {
        id: UID,
        treasury_cap: CoinManagerTreasuryCap<TESTI_TOKEN>,
        manager: CoinManager<TESTI_TOKEN>,
        claimed: Table<address, bool>
    }

    public fun maximum_supply(tracker: &ClaimTracker): u64 {
        coin_manager::maximum_supply(&tracker.manager)
    }

    public fun total_supply(tracker: &ClaimTracker): u64 {
        coin_manager::total_supply(&tracker.manager)
    }

    public fun remaining_supply(tracker: &ClaimTracker): u64  {
        coin_manager::available_supply(&tracker.manager)
    }

    public fun total_claimed(tracker: &ClaimTracker): u64 {
        table::length(&tracker.claimed)
    }

    fun init(w: TESTI_TOKEN, ctx: &mut TxContext) {
        let (cap, metacap, mut manager) = coin_manager::create(
            w,
            6, 
            b"TESTI", 
            b"Testi Token", 
            b"100M Max supply with free claim", 
            option::none(), 
            ctx
        );

        transfer::public_freeze_object(metacap);
        cap.enforce_maximum_supply(&mut manager, MAX_SUPPLY);

        cap.mint_and_transfer(&mut manager, INITIAL_SUPPLY, ctx.sender(), ctx);
        event::emit(TestEventTransfer { from: @iota_test, to: ctx.sender(), amount: INITIAL_SUPPLY });

        let tracker_uid = object::new(ctx);
        let tracker_addr = object::uid_to_address(&tracker_uid);

        transfer::share_object(ClaimTracker {
            id: tracker_uid,
            treasury_cap: cap,
            manager: manager,
            claimed: table::new(ctx),
        });
        
        event::emit(TestEventSharedObj { addr_obj: tracker_addr });
    }

    public fun claim(tracker: &mut ClaimTracker, ctx: &mut TxContext) {
        assert!(!table::contains(&tracker.claimed, ctx.sender()), EClaim);

        table::add(&mut tracker.claimed, ctx.sender(), true);

        coin_manager::mint_and_transfer(
            &tracker.treasury_cap, 
            &mut tracker.manager, 
            CLAIMABLE, 
            ctx.sender(), 
            ctx
        );

        event::emit(TestEventTransfer { from: @iota_test, to: ctx.sender(), amount: CLAIMABLE });
    }
    
    #[test]
    #[expected_failure(abort_code = EClaim, location = Self)]
    public fun test_claim() {
        use iota::test_scenario;

        let admin = @0xAD;
        let user = @0xB0B;
        
        let mut scenario = test_scenario::begin(admin);
        {
            let ctx = test_scenario::ctx(&mut scenario);
            init(TESTI_TOKEN {}, ctx);
        };

        test_scenario::next_tx(&mut scenario, user);
        {
            let mut tracker = test_scenario::take_shared<ClaimTracker>(&scenario);
            let ctx = test_scenario::ctx(&mut scenario);
            
            claim(&mut tracker, ctx);
            assert!(total_claimed(&tracker) == 1, 1);
            assert!(table::contains(&tracker.claimed, tx_context::sender(ctx)), 2);

            test_scenario::return_shared(tracker);
        };


        test_scenario::next_tx(&mut scenario, user);
        {
            let mut tracker = test_scenario::take_shared<ClaimTracker>(&scenario);
            let ctx = test_scenario::ctx(&mut scenario);
            
            claim(&mut tracker, ctx);

            test_scenario::return_shared(tracker);
        };
        
        test_scenario::end(scenario);
    }

    #[test]
    public fun test_transfer() {
        use iota::test_scenario;
        use iota::coin::{Self, Coin};

        let admin = @0xAD;
        let user = @0xB0B;
        let transfer_amount = 100;
        
        let mut scenario = test_scenario::begin(admin);
        {
            let ctx = test_scenario::ctx(&mut scenario);
            init(TESTI_TOKEN {}, ctx);
        };

        test_scenario::next_tx(&mut scenario, admin);
        {
            let mut coin = test_scenario::take_from_sender<Coin<TESTI_TOKEN>>(&scenario);
            assert!(coin::value(&coin) == INITIAL_SUPPLY, 3);
            
            transfer::public_transfer(coin::split(
                &mut coin, 
                transfer_amount, 
                test_scenario::ctx(&mut scenario)), 
                user
            );

            assert!(coin::value(&coin) == INITIAL_SUPPLY - transfer_amount, 4);
            test_scenario::return_to_sender(&scenario, coin);
        };

        test_scenario::next_tx(&mut scenario, user);
        {
            let coin = test_scenario::take_from_sender<Coin<TESTI_TOKEN>>(&scenario);
            assert!(coin::value(&coin) == transfer_amount, 5);
            test_scenario::return_to_sender(&scenario, coin);
        };
        
        test_scenario::end(scenario);
    }
}