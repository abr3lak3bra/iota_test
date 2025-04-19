module iota_test::testi_token {
    use iota::coin_manager::{Self, CoinManager, CoinManagerTreasuryCap};
    use iota::table::{Self, Table};
    use iota::event::Self;

    const MAX_SUPPLY: u64 = 100000000;

    const EClaim: u64 = 0;

    public struct TESTI_TOKEN has drop {}

    public struct Claim has copy, drop {
        claimer: address
    }

    public struct Transfer has copy, drop {
        addr: address
    }

    public struct ClaimTracker has key {
        id: UID,
        treasury_cap: CoinManagerTreasuryCap<TESTI_TOKEN>,
        manager: CoinManager<TESTI_TOKEN>,
        claimed: Table<address, bool>
    }

    fun init(w: TESTI_TOKEN, ctx: &mut TxContext) {
        let sender = tx_context::sender(ctx);
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

        // default: no emit any event
        cap.mint_and_transfer(&mut manager, 1000, sender, ctx);
        event::emit(Transfer { addr: sender });
        //

        transfer::share_object(ClaimTracker {
            id: object::new(ctx),
            treasury_cap: cap,
            manager: manager,
            claimed: table::new(ctx),
        });
    }

    public fun claim(tracker: &mut ClaimTracker, ctx: &mut TxContext) {
        let sender = tx_context::sender(ctx);
        assert!(!table::contains(&tracker.claimed, sender), EClaim);

        table::add(&mut tracker.claimed, sender, true);

        coin_manager::mint_and_transfer(
            &tracker.treasury_cap, 
            &mut tracker.manager, 
            1000, 
            sender,
            ctx
        );
    
        event::emit(Claim { claimer: sender });
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

            assert!(table::contains(&tracker.claimed, tx_context::sender(ctx)), 1);

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
}