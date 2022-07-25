module VaultExample::Vault {
    use std::event;
    use std::signer;
    use BasicCoin::BasicCoin;

    /// Error codes
    const ENOT_VAULT_EXAMPLE_ADDRESS: u64 = 0;
    const ENOT_PUBLISHED: u64 = 1;
    const EALREADY_PUBLISHED: u64 = 2;
    const EVAULT_IS_PAUSED: u64 = 3;

    struct ManagedCoin<phantom CoinType> has key {
        coin: u64
    }

    struct VaultStatus has key {
        is_paused: bool,
        deposit_event: event::EventHandle<DepositEvent>,
        withdraw_event: event::EventHandle<WithdrawEvent>,
    }

    struct DepositEvent has copy, drop, store {
        requester: address,
        amount: u64,
    }

    struct WithdrawEvent has copy, drop, store {
        requester: address,
        amount: u64,
    }

    fun init_module(creator: &signer) {
        move_to(
            creator,
            VaultStatus {
                is_paused: false,
                deposit_event: event::new_event_handle<DepositEvent>(creator),
                withdraw_event: event::new_event_handle<WithdrawEvent>(creator),
            }
        );
    }

    public fun create_coin<CoinType: drop>(account: &signer) {
        BasicCoin::publish_balance<CoinType>(account);
        assert!(signer::address_of(account) == @VaultExample, ENOT_VAULT_EXAMPLE_ADDRESS);
        assert!(!exists<ManagedCoin<CoinType>>(signer::address_of(account)), EALREADY_PUBLISHED);
        move_to(
            account,
            ManagedCoin<CoinType> { coin: 0 }
        );
    }

    public fun deposit<CoinType: drop>(requester: &signer, amount: u64, witness: CoinType) acquires VaultStatus, ManagedCoin {
        assert!(borrow_global_mut<VaultStatus>(@VaultExample).is_paused == false, EVAULT_IS_PAUSED);
        assert!(exists<ManagedCoin<CoinType>>(@VaultExample), ENOT_PUBLISHED);
        BasicCoin::transfer<CoinType>(requester, @VaultExample, amount, witness);

        let coin = &mut borrow_global_mut<ManagedCoin<CoinType>>(@VaultExample).coin;
        *coin = *coin + amount;

        event::emit_event(
            &mut borrow_global_mut<VaultStatus>(@VaultExample).deposit_event,
            DepositEvent {
                requester: signer::address_of(requester),
                amount,
            }
        );
    }

    public fun withdraw<CoinType: drop>(vault: &signer, requester: &signer, amount: u64, witness: CoinType) acquires VaultStatus, ManagedCoin {
        assert!(borrow_global_mut<VaultStatus>(@VaultExample).is_paused == false, EVAULT_IS_PAUSED);
        assert!(exists<ManagedCoin<CoinType>>(@VaultExample), ENOT_PUBLISHED);
        BasicCoin::transfer<CoinType>(vault, signer::address_of(requester), amount, witness);

        let coin = &mut borrow_global_mut<ManagedCoin<CoinType>>(@VaultExample).coin;
        *coin = *coin - amount;

        event::emit_event(
            &mut borrow_global_mut<VaultStatus>(@VaultExample).withdraw_event,
            WithdrawEvent {
                requester: signer::address_of(requester),
                amount,
            }
        );
    }

    public fun pause(account: &signer) acquires VaultStatus {
        assert!(signer::address_of(account) == @VaultExample, ENOT_VAULT_EXAMPLE_ADDRESS);
        let vault_status = borrow_global_mut<VaultStatus>(signer::address_of(account));
        vault_status.is_paused = true;
    }

    public fun unpause(account: &signer) acquires VaultStatus {
        assert!(signer::address_of(account) == @VaultExample, ENOT_VAULT_EXAMPLE_ADDRESS);
        let vault_status = borrow_global_mut<VaultStatus>(signer::address_of(account));
        vault_status.is_paused = false;
    }

    // Section: unit tests
    struct MyTestCoin has drop {}

    #[test(account = @VaultExample)]
    public entry fun module_can_initialize_correctly(account: signer) {
        let addr = signer::address_of(&account);

        assert!(!exists<VaultStatus>(addr), 0);
        init_module(&account);
        assert!(exists<VaultStatus>(addr), 0);
    }

    #[test(account = @VaultExample)]
    public entry fun admin_can_create_coin(account: signer) {
        let addr = signer::address_of(&account);
        init_module(&account);

        assert!(!exists<ManagedCoin<MyTestCoin>>(addr), 0);
        create_coin<MyTestCoin>(&account);
        assert!(exists<ManagedCoin<MyTestCoin>>(addr), 0);
    }

    #[test(account1 = @VaultExample, account2 = @Alice)]
    #[expected_failure(abort_code = 0)]
    public entry fun non_admin_cannot_create_coin(account1: signer, account2: signer) {
        init_module(&account1);
        create_coin<MyTestCoin>(&account2);
    }

    #[test(account1 = @VaultExample, account2 = @Alice)]
    public entry fun user_can_deposit(account1: signer, account2: signer) acquires VaultStatus, ManagedCoin {
        let addr1 = signer::address_of(&account1);
        let addr2 = signer::address_of(&account2);
        init_module(&account1);

        create_coin<MyTestCoin>(&account1);
        BasicCoin::publish_balance<MyTestCoin>(&account2);
        BasicCoin::mint(addr2, 10, MyTestCoin {});

        let coin = borrow_global<ManagedCoin<MyTestCoin>>(addr1).coin;
        assert!(coin == 0, 0);

        let deposit_amount = 10;
        deposit(&account2, deposit_amount, MyTestCoin {});

        let coin = borrow_global<ManagedCoin<MyTestCoin>>(addr1).coin;
        assert!(coin == deposit_amount, 0);
    }

    #[test(account1 = @VaultExample, account2 = @Alice)]
    public entry fun user_can_withdraw(account1: signer, account2: signer) acquires VaultStatus, ManagedCoin {
        let addr1 = signer::address_of(&account1);
        let addr2 = signer::address_of(&account2);
        init_module(&account1);

        create_coin<MyTestCoin>(&account1);
        BasicCoin::publish_balance<MyTestCoin>(&account2);
        BasicCoin::mint(addr2, 10, MyTestCoin {});

        let deposit_amount = 10;
        deposit(&account2, deposit_amount, MyTestCoin {});

        let coin = borrow_global<ManagedCoin<MyTestCoin>>(addr1).coin;
        assert!(coin == deposit_amount, 0);

        let withdraw_amount = deposit_amount;
        withdraw(&account1, &account2, withdraw_amount, MyTestCoin {});

        let coin = borrow_global<ManagedCoin<MyTestCoin>>(addr1).coin;
        assert!(coin == 0, 0);
    }

    #[test(account1 = @VaultExample, account2 = @Alice)]
    #[expected_failure(abort_code = 3)]
    public entry fun user_cannot_deposit_when_vault_is_paused(account1: signer, account2: signer) acquires VaultStatus, ManagedCoin {
        let addr2 = signer::address_of(&account2);
        init_module(&account1);

        create_coin<MyTestCoin>(&account1);
        BasicCoin::publish_balance<MyTestCoin>(&account2);
        BasicCoin::mint(addr2, 10, MyTestCoin {});

        pause(&account1);

        let deposit_amount = 10;
        deposit(&account2, deposit_amount, MyTestCoin {});
    }

    #[test(account1 = @VaultExample, account2 = @Alice)]
    #[expected_failure(abort_code = 3)]
    public entry fun user_cannot_withdraw_when_vault_is_paused(account1: signer, account2: signer) acquires VaultStatus, ManagedCoin {
        let addr2 = signer::address_of(&account2);
        init_module(&account1);

        create_coin<MyTestCoin>(&account1);
        BasicCoin::publish_balance<MyTestCoin>(&account2);
        BasicCoin::mint(addr2, 10, MyTestCoin {});

        let deposit_amount = 10;
        deposit(&account2, deposit_amount, MyTestCoin {});

        pause(&account1);

        let withdraw_amount = deposit_amount;
        withdraw(&account1, &account2, withdraw_amount, MyTestCoin {});
    }

    #[test(account = @VaultExample)]
    public entry fun admin_can_pause(account: signer) acquires VaultStatus {
        let addr = signer::address_of(&account);
        init_module(&account);

        let is_paused = borrow_global<VaultStatus>(addr).is_paused;
        assert!(is_paused == false, 0);

        pause(&account);

        let is_paused = borrow_global<VaultStatus>(addr).is_paused;
        assert!(is_paused == true, 0);
    }

    #[test(account = @VaultExample)]
    public entry fun admin_can_unpause(account: signer) acquires VaultStatus {
        let addr = signer::address_of(&account);
        init_module(&account);

        pause(&account);

        let is_paused = borrow_global<VaultStatus>(addr).is_paused;
        assert!(is_paused == true, 0);

        unpause(&account);

        let is_paused = borrow_global<VaultStatus>(addr).is_paused;
        assert!(is_paused == false, 0);
    }

    #[test(account1 = @VaultExample, account2 = @Alice)]
    #[expected_failure(abort_code = 0)]
    public entry fun non_admin_cannot_pause(account1: signer, account2: signer) acquires VaultStatus {
        let addr1 = signer::address_of(&account1);
        init_module(&account1);

        let is_paused = borrow_global<VaultStatus>(addr1).is_paused;
        assert!(is_paused == false, 0);

        pause(&account2);

        let is_paused = borrow_global<VaultStatus>(addr1).is_paused;
        assert!(is_paused == false, 0);
    }

    #[test(account1 = @VaultExample, account2 = @Alice)]
    #[expected_failure(abort_code = 0)]
    public entry fun non_admin_cannot_unpause(account1: signer, account2: signer) acquires VaultStatus {
        let addr1 = signer::address_of(&account1);
        init_module(&account1);

        pause(&account1);

        let is_paused = borrow_global<VaultStatus>(addr1).is_paused;
        assert!(is_paused == true, 0);

        unpause(&account2);

        let is_paused = borrow_global<VaultStatus>(addr1).is_paused;
        assert!(is_paused == true, 0);
    }
}
