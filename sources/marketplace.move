/* 
    This quest features a marketplace where users can create shops and sell items. Every shop is a 
    global shared object that is managed by the shop owner, which is designated by the ownership of 
    the shop owner capability. The shop owner can add items to their shop, unlist items, and 
    withdraw the profit from their shop. Users can purchase items from shops and will receive a 
    purchased item receipt for each item purchased.

    Shops: 
        A Shop is a global shared object that is managed by the shop owner. The shop object holds 
        items and the balance of SUI coins in the shop. 
    
    Shop ownership: 
        Ownership of the Shop object is represented by holding the shop owner capability object. 
        The shop owner has the ability to add items to the shop, unlist items, and withdraw from 
        the shop. 

    Adding items to a shop: 
        The shop owner can add items to their shop with the add_item function.

    Purchasing an item: 
        Anyone has the ability to purchase an item that is listed. When an item is purchased, the 
        buyer will receive a separate purchased item receipt for each item purchased. The purchased 
        item receipt is a object that is owned by the buyer and is used to represent a purchased 
        item.

        The buyer must provide a payment coin for the item. The payment coin must be equal to or 
        greater than the price of the item. If the payment coin is greater than the price of the
        item, the change will be left in the payment coin. 

        The profit from the sale of the item will be added to the shop balance. 

        The available supply of the item will be decreased by the quantity purchased. If the 
        available supply of the item is 0, the item will be unlisted.

    Unlisting an item: 
        The shop owner can unlist an item from their shop with the unlist_item function. When an 
        item is unlisted, it will no longer be available for purchase.

    Withdrawing from a shop: 
        The shop owner can withdraw SUI from their shop with the withdraw_from_shop function. The shop 
        owner can withdraw any amount from their shop that is equal to or below the total amount in 
        the shop. The amount withdrawn will be sent to the recipient address specified.    
*/
module overmind::marketplace {
    //==============================================================================================
    // Dependencies
    //==============================================================================================
    use sui::coin;
    use sui::event;
    use std::vector;
    use sui::sui::SUI;
    use sui::transfer;
    use sui::url::{Self, Url};
    use sui::object::{Self, UID, ID};
    use sui::tx_context::TxContext;
    use std::string::{Self, String};
    use sui::balance::{Self, Balance};

    #[test_only]
    use sui::test_scenario;
    #[test_only]
    use sui::test_utils::assert_eq;

    //==============================================================================================
    // Constants - Add your constants here (if any)
    //==============================================================================================

    //==============================================================================================
    // Error codes - DO NOT MODIFY
    //==============================================================================================
    const ENotShopOwner: u64 = 1;
    const EInvalidWithdrawalAmount: u64 = 2;
    const EInvalidQuantity: u64 = 3;
    const EInsufficientPayment: u64 = 4;
    const EInvalidItemId: u64 = 5;
    const EInvalidPrice: u64 = 6;
    const EInvalidSupply: u64 = 7;
    const EItemIsNotListed: u64 = 8;

    //==============================================================================================
    // Module Structs - DO NOT MODIFY
    //==============================================================================================

    /*
        The shop struct represents a shop in the marketplace. A shop is a global shared object that
        is managed by the shop owner. The shop owner is designated by the ownership of the shop
        owner capability. 
        @param id - The object id of the shop object.
        @param shop_owner_cap - The object id of the shop owner capability.
        @param balance - The balance of SUI coins in the shop.
        @param items - The items in the shop.
        @param item_count - The number of items in the shop. Including items that are not listed or 
            sold out.
    */
	struct Shop has key {
		id: UID,
        shop_owner_cap: ID,
		balance: Balance<SUI>,
		items: vector<Item>,
        item_count: u64
	}

    /*
        The shop owner capability struct represents the ownership of a shop. The shop
        owner capability is a object that is owned by the shop owner and is used to manage the shop.
        @param id - The object id of the shop owner capability object.
        @param shop - The object id of the shop object.
    */
    struct ShopOwnerCapability has key {
        id: UID,
        shop: ID,
    }

    /*
        The item struct represents an item in a shop. An item is a product that can be purchased
        from a shop.
        @param id - The id of the item object. This is the index of the item in the shop's items
            vector.
        @param title - The title of the item.
        @param description - The description of the item.
        @param price - The price of the item (price per each quantity).
        @param url - The url of item image.
        @param listed - Whether the item is listed. If the item is not listed, it will not be 
            available for purchase.
        @param category - The category of the item.
        @param total_supply - The total supply of the item.
        @param available - The available supply of the item. Will be less than or equal to the total
            supply and will start at the total supply and decrease as items are purchased.
    */
    struct Item has store {
		id: u64,
		title: String,
		description: String,
		price: u64,
		url: Url,
        listed: bool,
        category: u8,
        total_supply: u64,
        available: u64
	}

    /*
        The purchased item struct represents a purchased item receipt. A purchased item receipt is
        a object that is owned by the buyer and is used to represent a purchased item.
        @param id - The object id of the purchased item object.
        @param shop_id - The object id of the shop object.
        @param item_id - The id of the item object.
    */
    struct PurchasedItem has key {
        id: UID,
        shop_id: ID, 
        item_id: u64
    }

    //==============================================================================================
    // Event structs - DO NOT MODIFY
    //==============================================================================================

    /*
        Event to be emitted when a shop is created.
        @param shop_id - The id of the shop object.
        @param shop_owner_cap_id - The id of the shop owner capability object.
    */
    struct ShopCreated has copy, drop {
        shop_id: ID,
        shop_owner_cap_id: ID,
    }

    /*
        Event to be emitted when an item is added to a shop.
        @param item - The id of the item object.
    */
    struct ItemAdded has copy, drop {
        shop_id: ID,
        item: u64,
    }

    /*
        Event to be emitted when an item is purchased.
        @param item - The id of the item object.
        @param quantity - The quantity of the item purchased.
        @param buyer - The address of the buyer.
    */
    struct ItemPurchased has copy, drop {
        shop_id: ID,
        item_id: u64, 
        quantity: u64,
        buyer: address,
    }

    /*
        Event to be emitted when an item is unlisted.
        @param item - The id of the item object.
    */
    struct ItemUnlisted has copy, drop {
        shop_id: ID,
        item_id: u64
    }

    /*
        Event to be emitted when a shop owner withdraws from their shop.
        @param shop_id - The id of the shop object.
        @param amount - The amount withdrawn.
        @param recipient - The address of the recipient of the withdrawal.
    */
    struct ShopWithdrawal has copy, drop {
        shop_id: ID,
        amount: u64,
        recipient: address
    }

    //==============================================================================================
    // Functions
    //==============================================================================================

	/*
        Creates a new shop for the recipient and emits a ShopCreated event.
        @param recipient - The address of the recipient of the shop.
        @param ctx - The transaction context.
	*/
	public fun create_shop(recipient: address, ctx: &mut TxContext) {
        
	}

    /*
        Adds a new item to the shop and emits an ItemAdded event. Abort if the shop owner capability
        does not match the shop, if the price is not above 0, or if the supply is not above 0.
        @param shop - The shop to add the item to.
        @param shop_owner_cap - The shop owner capability of the shop.
        @param title - The title of the item.
        @param description - The description of the item.
        @param url - The url of the item.
        @param price - The price of the item.
        @param supply - The initial supply of the item.
        @param category - The category of the item.
        @param ctx - The transaction context.
    */
    public fun add_item(
        shop: &mut Shop,
        shop_owner_cap: &ShopOwnerCapability, 
        title: vector<u8>,
        description: vector<u8>,
        url: vector<u8>,
        price: u64, 
        supply: u64, 
        category: u8
    ) {
        
    }

    /*
        Unlists an item from the shop and emits an ItemUnlisted event. Abort if the shop owner 
        capability does not match the shop or if the item id is invalid.
        @param shop - The shop to unlist the item from.
        @param shop_owner_cap - The shop owner capability of the shop.
        @param item_id - The id of the item to unlist.
    */
    public fun unlist_item(
        shop: &mut Shop,
        shop_owner_cap: &ShopOwnerCapability,
        item_id: u64
    ) {
        
    }

    /*
        Purchases an item from the shop and emits an ItemPurchased event. Abort if the item id is
        invalid, the payment coin is insufficient, if the item is unlisted, or the shop does not 
        have enough available supply. Emit an ItemUnlisted event if the last item(s) are purchased.
        @param shop - The shop to purchase the item from.
        @param item_id - The id of the item to purchase.
        @param quantity - The quantity of the item to purchase.
        @param recipient - The address of the recipient of the item.
        @param payment_coin - The payment coin for the item.
        @param ctx - The transaction context.
    */
    public fun purchase_item(
        shop: &mut Shop, 
        item_id: u64,
        quantity: u64,
        recipient: address,
        payment_coin: &mut coin::Coin<SUI>,
        ctx: &mut TxContext
    ) {

    }

    /*
        Withdraws SUI from the shop to the recipient and emits a ShopWithdrawal event. Abort if the 
        shop owner capability does not match the shop or if the amount is invalid.
        @param shop - The shop to withdraw from.
        @param shop_owner_cap - The shop owner capability of the shop.
        @param amount - The amount to withdraw.
        @param recipient - The address of the recipient of the withdrawal.
        @param ctx - The transaction context.
    */
    public fun withdraw_from_shop(
        shop: &mut Shop,
        shop_owner_cap: &ShopOwnerCapability,
        amount: u64,
        recipient: address,
        ctx: &mut TxContext
    ) {
        
    }

    //==============================================================================================
    // Helper functions - Add your helper functions here (if any)
    //==============================================================================================

    //==============================================================================================
    // Validation functions - Add your validation functions here (if any)
    //==============================================================================================

    //==============================================================================================
    // Tests - DO NOT MODIFY
    //==============================================================================================
    #[test]
    public fun test_create_shop_success_create_shop_for_user() {
        let shop_owner = @0xa;

        let scenario_val = test_scenario::begin(shop_owner);
        let scenario = &mut scenario_val;

        {
            create_shop(shop_owner, test_scenario::ctx(scenario));
        };
        let tx = test_scenario::next_tx(scenario, shop_owner);
        let expected_events_emitted = 1;
        assert_eq(
            test_scenario::num_user_events(&tx),
            expected_events_emitted
        );

        {
            let shop_owner_cap = test_scenario::take_from_sender<ShopOwnerCapability>(scenario);
            let shop = test_scenario::take_shared<Shop>(scenario);

            assert_eq(shop_owner_cap.shop, sui::object::uid_to_inner(&shop.id));
            
            test_scenario::return_to_sender(scenario, shop_owner_cap);
            test_scenario::return_shared(shop);
        };
        let tx = test_scenario::end(scenario_val);
        let expected_events_emitted = 0;
        assert_eq(
            test_scenario::num_user_events(&tx),
            expected_events_emitted
        );
    }

    #[test]
    public fun test_create_shop_success_create_multiple_shops_for_user() {
        let shop_owner = @0xa;

        let scenario_val = test_scenario::begin(shop_owner);
        let scenario = &mut scenario_val;

        {
            create_shop(shop_owner, test_scenario::ctx(scenario));
        };
        let tx = test_scenario::next_tx(scenario, shop_owner);
        let expected_events_emitted = 1;
        assert_eq(
            test_scenario::num_user_events(&tx),
            expected_events_emitted
        );

        {
            let shop_owner_cap = test_scenario::take_from_sender<ShopOwnerCapability>(scenario);
            let shop = test_scenario::take_shared<Shop>(scenario);

            assert_eq(shop_owner_cap.shop, sui::object::uid_to_inner(&shop.id));
            
            test_scenario::return_to_sender(scenario, shop_owner_cap);
            test_scenario::return_shared(shop);
        };
        let tx = test_scenario::next_tx(scenario, shop_owner);
        let expected_events_emitted = 0;
        assert_eq(
            test_scenario::num_user_events(&tx),
            expected_events_emitted
        );

        {
            create_shop(shop_owner, test_scenario::ctx(scenario));
        };
        let tx = test_scenario::next_tx(scenario, shop_owner);
        let expected_events_emitted = 1;
        assert_eq(
            test_scenario::num_user_events(&tx),
            expected_events_emitted
        );

        {
            let shop_owner_cap = test_scenario::take_from_sender<ShopOwnerCapability>(scenario);
            let shop = test_scenario::take_shared<Shop>(scenario);

            assert_eq(shop_owner_cap.shop, sui::object::uid_to_inner(&shop.id));
            
            test_scenario::return_to_sender(scenario, shop_owner_cap);
            test_scenario::return_shared(shop);
        };
        let tx = test_scenario::next_tx(scenario, shop_owner);
        let expected_events_emitted = 0;
        assert_eq(
            test_scenario::num_user_events(&tx),
            expected_events_emitted
        );

        {
            create_shop(shop_owner, test_scenario::ctx(scenario));
        };
        let tx = test_scenario::next_tx(scenario, shop_owner);
        let expected_events_emitted = 1;
        assert_eq(
            test_scenario::num_user_events(&tx),
            expected_events_emitted
        );

        {
            let shop_owner_cap = test_scenario::take_from_sender<ShopOwnerCapability>(scenario);
            let shop = test_scenario::take_shared<Shop>(scenario);

            assert_eq(shop_owner_cap.shop, sui::object::uid_to_inner(&shop.id));
            
            test_scenario::return_to_sender(scenario, shop_owner_cap);
            test_scenario::return_shared(shop);
        };
        let tx = test_scenario::end(scenario_val);
        let expected_events_emitted = 0;
        assert_eq(
            test_scenario::num_user_events(&tx),
            expected_events_emitted
        );
    }

    #[test]
    public fun test_create_shop_success_shop_for_multiple_users() {
        let user1 = @0xa;
        let user2 = @0xb;


        let scenario_val = test_scenario::begin(user1);
        let scenario = &mut scenario_val;
        {
            create_shop(user1, test_scenario::ctx(scenario));
        };

        let tx = test_scenario::next_tx(scenario, user1);
        let expected_events_emitted = 1;
        assert_eq(
            test_scenario::num_user_events(&tx),
            expected_events_emitted
        );

        {
            let shop_owner_cap_of_user_1 = test_scenario::take_from_sender<ShopOwnerCapability>(scenario);
            let shop_of_user_1 = test_scenario::take_shared<Shop>(scenario);

            assert_eq(shop_owner_cap_of_user_1.shop, sui::object::uid_to_inner(&shop_of_user_1.id));
            
            test_scenario::return_to_sender(scenario, shop_owner_cap_of_user_1);
            test_scenario::return_shared(shop_of_user_1);
        };
        
        let tx = test_scenario::next_tx(scenario, user2);
        let expected_events_emitted = 0;
        assert_eq(
            test_scenario::num_user_events(&tx),
            expected_events_emitted
        );

        {
            create_shop(user2, test_scenario::ctx(scenario));
        };

        let tx = test_scenario::next_tx(scenario, user2);
        let expected_events_emitted = 1;
        assert_eq(
            test_scenario::num_user_events(&tx),
            expected_events_emitted
        );

        {
            let shop_owner_cap_of_user_2 = test_scenario::take_from_sender<ShopOwnerCapability>(scenario);
            let shop_of_user_2 = test_scenario::take_shared<Shop>(scenario);

            assert_eq(shop_owner_cap_of_user_2.shop, sui::object::uid_to_inner(&shop_of_user_2.id));
            
            test_scenario::return_to_sender(scenario, shop_owner_cap_of_user_2);
            test_scenario::return_shared(shop_of_user_2);
        };

        let tx = test_scenario::end(scenario_val);
        let expected_events_emitted = 0;
        assert_eq(
            test_scenario::num_user_events(&tx),
            expected_events_emitted
        );

    }

    #[test]
    public fun test_add_item_success_added_one_item() {
        let shop_owner = @0xa;

        let scenario_val = test_scenario::begin(shop_owner);
        let scenario = &mut scenario_val;

        {
            create_shop(shop_owner, test_scenario::ctx(scenario));
        };
        let tx = test_scenario::next_tx(scenario, shop_owner);
        let expected_events_emitted = 1;
        assert_eq(
            test_scenario::num_user_events(&tx),
            expected_events_emitted
        );

        let expected_title = b"title";
        let expected_description = b"description";
        let expected_url = b"url";
        let expected_price = 1000000000; // 1 SUI
        let expected_category = 3;
        let expected_supply = 34;
        {
            let shop_owner_cap  = 
                test_scenario::take_from_sender<ShopOwnerCapability>(scenario);
            let shop = test_scenario::take_shared<Shop>(scenario);

            add_item(
                &mut shop, 
                &shop_owner_cap,
                expected_title, 
                expected_description, 
                expected_url, 
                expected_price, 
                expected_supply, 
                expected_category
            );

            test_scenario::return_to_sender(scenario, shop_owner_cap);
            test_scenario::return_shared(shop);
        };
        let tx = test_scenario::next_tx(scenario, shop_owner);
        let expected_events_emitted = 1;
        assert_eq(
            test_scenario::num_user_events(&tx),
            expected_events_emitted
        );

        {

            let expected_item_length = 1;

            let shop = test_scenario::take_shared<Shop>(scenario);

            assert_eq(vector::length(&shop.items), expected_item_length);

            let item_id = 0;
            let item_ref = vector::borrow(&shop.items, item_id);

            assert_eq(item_ref.id, item_id);
            assert_eq(item_ref.title, string::utf8(expected_title));
            assert_eq(item_ref.description, string::utf8(expected_description));
            assert_eq(item_ref.url, url::new_unsafe_from_bytes(expected_url));
            assert_eq(item_ref.price, expected_price);
            assert_eq(item_ref.category, expected_category);
            assert_eq(item_ref.total_supply, expected_supply);
            assert_eq(item_ref.available, expected_supply);
            assert_eq(item_ref.listed, true);

            test_scenario::return_shared(shop);
        };
        let tx = test_scenario::end(scenario_val);
        let expected_events_emitted = 0;
        assert_eq(
            test_scenario::num_user_events(&tx),
            expected_events_emitted
        );

    }

    #[test, expected_failure(abort_code = EInvalidPrice)]
    public fun test_add_item_failure_zero_price() {
        let shop_owner = @0xa;

        let scenario_val = test_scenario::begin(shop_owner);
        let scenario = &mut scenario_val;

        {
            create_shop(shop_owner, test_scenario::ctx(scenario));
        };
        test_scenario::next_tx(scenario, shop_owner);

        let expected_title = b"title";
        let expected_description = b"description";
        let expected_url = b"url";
        let expected_price = 0; 
        let expected_category = 3;
        let expected_supply = 34;
        {
            let shop_owner_cap  = 
                test_scenario::take_from_sender<ShopOwnerCapability>(scenario);
            let shop = test_scenario::take_shared<Shop>(scenario);

            add_item(
                &mut shop, 
                &shop_owner_cap,
                expected_title, 
                expected_description, 
                expected_url, 
                expected_price, 
                expected_supply, 
                expected_category
            );

            test_scenario::return_to_sender(scenario, shop_owner_cap);
            test_scenario::return_shared(shop);
        };
        test_scenario::end(scenario_val);
    }

    #[test, expected_failure(abort_code = EInvalidSupply)]
    public fun test_add_item_failure_zero_supply() {
        let shop_owner = @0xa;

        let scenario_val = test_scenario::begin(shop_owner);
        let scenario = &mut scenario_val;

        {
            create_shop(shop_owner, test_scenario::ctx(scenario));
        };
        test_scenario::next_tx(scenario, shop_owner);

        let expected_title = b"title";
        let expected_description = b"description";
        let expected_url = b"url";
        let expected_price = 1000000000; // 1 SUI
        let expected_category = 3;
        let expected_supply = 0;
        {
            let shop_owner_cap  = 
                test_scenario::take_from_sender<ShopOwnerCapability>(scenario);
            let shop = test_scenario::take_shared<Shop>(scenario);

            add_item(
                &mut shop, 
                &shop_owner_cap,
                expected_title, 
                expected_description, 
                expected_url, 
                expected_price, 
                expected_supply, 
                expected_category
            );

            test_scenario::return_to_sender(scenario, shop_owner_cap);
            test_scenario::return_shared(shop);
        };
        test_scenario::end(scenario_val);
    }

    #[test]
    public fun test_add_item_success_added_multiple_items() {
        let shop_owner = @0xa;

        let scenario_val = test_scenario::begin(shop_owner);
        let scenario = &mut scenario_val;

        {
            create_shop(shop_owner, test_scenario::ctx(scenario));
        };

        {
            let expected_title = b"title";
            let expected_description = b"description";
            let expected_url = b"url";
            let expected_price = 1000000000; // 1 SUI
            let expected_category = 3;
            let expected_supply = 34;
            test_scenario::next_tx(scenario, shop_owner);
            {
                let shop_owner_cap  = 
                    test_scenario::take_from_sender<ShopOwnerCapability>(scenario);
                let shop = test_scenario::take_shared<Shop>(scenario);

                add_item(
                    &mut shop, 
                    &shop_owner_cap,
                    expected_title, 
                    expected_description, 
                    expected_url, 
                    expected_price, 
                    expected_supply, 
                    expected_category
                );

                test_scenario::return_to_sender(scenario, shop_owner_cap);
                test_scenario::return_shared(shop);
            };

            test_scenario::next_tx(scenario, shop_owner);
            {

                let expected_item_length = 1;

                let shop = test_scenario::take_shared<Shop>(scenario);

                assert_eq(vector::length(&shop.items), expected_item_length);

                let item_id = 0;
                let item_ref = vector::borrow(&shop.items, item_id);

                assert_eq(item_ref.id, item_id);
                assert_eq(item_ref.title, string::utf8(expected_title));
                assert_eq(item_ref.description, string::utf8(expected_description));
                assert_eq(item_ref.url, url::new_unsafe_from_bytes(expected_url));
                assert_eq(item_ref.price, expected_price);
                assert_eq(item_ref.category, expected_category);
                assert_eq(item_ref.total_supply, expected_supply);
                assert_eq(item_ref.available, expected_supply);
                assert_eq(item_ref.listed, true);

                test_scenario::return_shared(shop);
            };
        };

        {
            let expected_title = b"adf";
            let expected_description = b"descdfription";
            let expected_url = b"usrl";
            let expected_price = 45000000000; // 45 SUI
            let expected_category = 2;
            let expected_supply = 1;
            test_scenario::next_tx(scenario, shop_owner);
            {
                let shop_owner_cap  = 
                    test_scenario::take_from_sender<ShopOwnerCapability>(scenario);
                let shop = test_scenario::take_shared<Shop>(scenario);

                add_item(
                    &mut shop, 
                    &shop_owner_cap,
                    expected_title, 
                    expected_description, 
                    expected_url, 
                    expected_price, 
                    expected_supply, 
                    expected_category
                );

                test_scenario::return_to_sender(scenario, shop_owner_cap);
                test_scenario::return_shared(shop);
            };

            test_scenario::next_tx(scenario, shop_owner);
            {
                let expected_item_length = 2;
                let shop = test_scenario::take_shared<Shop>(scenario);

                assert_eq(vector::length(&shop.items), expected_item_length);

                let item_id = 1;
                let item_ref = vector::borrow(&shop.items, item_id);

                assert_eq(item_ref.id, item_id);
                assert_eq(item_ref.title, string::utf8(expected_title));
                assert_eq(item_ref.description, string::utf8(expected_description));
                assert_eq(item_ref.url, url::new_unsafe_from_bytes(expected_url));
                assert_eq(item_ref.price, expected_price);
                assert_eq(item_ref.category, expected_category);
                assert_eq(item_ref.total_supply, expected_supply);
                assert_eq(item_ref.available, expected_supply);
                assert_eq(item_ref.listed, true);

                test_scenario::return_shared(shop);
            };
        };

        {
            let expected_title = b"shoes";
            let expected_description = b"just do it";
            let expected_url = b"photo.com";
            let expected_price = 200000000; // .2 SUI
            let expected_category = 1;
            let expected_supply = 2;
            test_scenario::next_tx(scenario, shop_owner);
            {
                let shop_owner_cap  = 
                    test_scenario::take_from_sender<ShopOwnerCapability>(scenario);
                let shop = test_scenario::take_shared<Shop>(scenario);

                add_item(
                    &mut shop, 
                    &shop_owner_cap,
                    expected_title, 
                    expected_description, 
                    expected_url, 
                    expected_price, 
                    expected_supply, 
                    expected_category
                );

                test_scenario::return_to_sender(scenario, shop_owner_cap);
                test_scenario::return_shared(shop);
            };

            test_scenario::next_tx(scenario, shop_owner);
            {

                let expected_item_length = 3;

                let shop = test_scenario::take_shared<Shop>(scenario);

                assert_eq(vector::length(&shop.items), expected_item_length);

                let item_id = 2;
                let item_ref = vector::borrow(&shop.items, item_id);

                assert_eq(item_ref.id, item_id);
                assert_eq(item_ref.title, string::utf8(expected_title));
                assert_eq(item_ref.description, string::utf8(expected_description));
                assert_eq(item_ref.url, url::new_unsafe_from_bytes(expected_url));
                assert_eq(item_ref.price, expected_price);
                assert_eq(item_ref.category, expected_category);
                assert_eq(item_ref.total_supply, expected_supply);
                assert_eq(item_ref.available, expected_supply);
                assert_eq(item_ref.listed, true);

                test_scenario::return_shared(shop);
            };
        };

        test_scenario::end(scenario_val);
    }

    #[test, expected_failure(abort_code = ENotShopOwner)]
    public fun test_add_item_failure_wrong_shop_owner_cap() {
        let user1 = @0xa;
        let user2 = @0xb;

        let scenario_val = test_scenario::begin(user1);
        let scenario = &mut scenario_val;

        {
            create_shop(user2, test_scenario::ctx(scenario));
            create_shop(user1, test_scenario::ctx(scenario));
        };
        test_scenario::next_tx(scenario, user2);

        {
            let shop_owner_cap_of_user_2  = 
                test_scenario::take_from_sender<ShopOwnerCapability>(scenario);
            let shop_of_user_1 = test_scenario::take_shared<Shop>(scenario);
            
            add_item(
                &mut shop_of_user_1, 
                &shop_owner_cap_of_user_2,
                b"title", 
                b"description", 
                b"url", 
                1000000000, // 1 SUI
                34, 
                3
            );

            test_scenario::return_to_sender(scenario, shop_owner_cap_of_user_2);
            test_scenario::return_shared(shop_of_user_1);
        };
        test_scenario::end(scenario_val);
    }

    #[test]
    public fun test_purchase_item_success_purchase_one_item_one_quantity() {
        let shop_owner = @0xa;
        let buyer = @0xb;

        let scenario_val = test_scenario::begin(shop_owner);
        let scenario = &mut scenario_val;

        {
            create_shop(shop_owner, test_scenario::ctx(scenario));
        };
        test_scenario::next_tx(scenario, shop_owner);

        {
            let shop_owner_cap  = 
                test_scenario::take_from_sender<ShopOwnerCapability>(scenario);
            let shop = test_scenario::take_shared<Shop>(scenario);

            add_item(
                &mut shop, 
                &shop_owner_cap,
                b"title", 
                b"description", 
                b"url", 
                1000000000, // 1 SUI
                34, 
                3
            );

            test_scenario::return_to_sender(scenario, shop_owner_cap);
            test_scenario::return_shared(shop);
        };
        let tx = test_scenario::next_tx(scenario, buyer);
        let expected_events_emitted = 1;
        assert_eq(
            test_scenario::num_user_events(&tx),
            expected_events_emitted
        );

        {
            let shop = test_scenario::take_shared<Shop>(scenario);
            let item_id = 0;
            let item_ref = vector::borrow(&shop.items, item_id);

            let price = item_ref.price;
            let quantity_to_buy = 1;

            let payment_coin = sui::coin::mint_for_testing<SUI>(
                price * quantity_to_buy, 
                test_scenario::ctx(scenario)
            );


            purchase_item(
                &mut shop, 
                item_ref.id, 
                quantity_to_buy, 
                buyer, 
                &mut payment_coin, 
                test_scenario::ctx(scenario)
            );

            test_scenario::return_shared(shop);

            coin::destroy_zero(payment_coin);
        };
        let tx = test_scenario::next_tx(scenario, buyer);
        let expected_events_emitted = 1;
        assert_eq(
            test_scenario::num_user_events(&tx),
            expected_events_emitted
        );

        {
            let shop = test_scenario::take_shared<Shop>(scenario);
            let item_id = 0;
            let item_ref = vector::borrow(&shop.items, item_id);

            let expected_total_supply = 34;
            let expected_quantity_purchased = 1;

            assert_eq(item_ref.available, expected_total_supply - expected_quantity_purchased);
            assert_eq(balance::value(&shop.balance), item_ref.price);
            assert_eq(item_ref.listed, true);

            let purchased_item = test_scenario::take_from_sender<PurchasedItem>(scenario);
            assert_eq(purchased_item.item_id, item_ref.id);

            assert_eq(
                vector::length(&test_scenario::ids_for_sender<PurchasedItem>(scenario)), 
                1
            );

            test_scenario::return_shared(shop);
            test_scenario::return_to_sender(scenario, purchased_item);
        };
        let tx = test_scenario::end(scenario_val);
        let expected_events_emitted = 0;
        assert_eq(
            test_scenario::num_user_events(&tx),
            expected_events_emitted
        );
    }

    #[test]
    public fun test_purchase_item_success_purchase_one_item_full_quantity() {
        let shop_owner = @0xa;
        let buyer = @0xb;

        let scenario_val = test_scenario::begin(shop_owner);
        let scenario = &mut scenario_val;

        {
            create_shop(shop_owner, test_scenario::ctx(scenario));
        };
        test_scenario::next_tx(scenario, shop_owner);

        {
            let shop_owner_cap  = 
                test_scenario::take_from_sender<ShopOwnerCapability>(scenario);
            let shop = test_scenario::take_shared<Shop>(scenario);

            add_item(
                &mut shop, 
                &shop_owner_cap,
                b"title", 
                b"description", 
                b"url", 
                1000000000, // 1 SUI
                10, 
                3
            );

            test_scenario::return_to_sender(scenario, shop_owner_cap);
            test_scenario::return_shared(shop);
        };
        test_scenario::next_tx(scenario, buyer);

        {
            let shop = test_scenario::take_shared<Shop>(scenario);
            let item_id = 0;
            let item_ref = vector::borrow(&shop.items, item_id);

            let price = item_ref.price;

            let quantity_to_buy = 10;

            let payment_coin = sui::coin::mint_for_testing<SUI>(
                price * quantity_to_buy,
                test_scenario::ctx(scenario)
            );

            purchase_item(
                &mut shop, 
                item_ref.id, 
                quantity_to_buy, 
                buyer, 
                &mut payment_coin, 
                test_scenario::ctx(scenario)
            );

            test_scenario::return_shared(shop);

            coin::destroy_zero(payment_coin);
        };
        let tx = test_scenario::next_tx(scenario, buyer);
        let expected_events_emitted = 2;
        assert_eq(
            test_scenario::num_user_events(&tx),
            expected_events_emitted
        );

        {
            let shop = test_scenario::take_shared<Shop>(scenario);
            let item_id = 0;
            let item_ref = vector::borrow(&shop.items, item_id);

            let expected_total_supply = 10;
            let expected_quantity_purchased = 10;

            assert_eq(item_ref.available, expected_total_supply - expected_quantity_purchased);
            assert_eq(balance::value(&shop.balance), item_ref.price * expected_quantity_purchased);
            assert_eq(item_ref.listed, false);

            let purchased_item = test_scenario::take_from_sender<PurchasedItem>(scenario);
            assert_eq(purchased_item.item_id, item_ref.id);

            assert_eq(
                vector::length(&test_scenario::ids_for_sender<PurchasedItem>(scenario)), 
                10
            );

            test_scenario::return_shared(shop);
            test_scenario::return_to_sender(scenario, purchased_item);
        };
        test_scenario::end(scenario_val);
    }

    #[test]
    public fun test_purchase_item_success_purchase_one_item_multiple_purchases() {
        let shop_owner = @0xa;
        let buyer = @0xb;

        let scenario_val = test_scenario::begin(shop_owner);
        let scenario = &mut scenario_val;

        {
            create_shop(shop_owner, test_scenario::ctx(scenario));
        };
        test_scenario::next_tx(scenario, shop_owner);

        {
            let shop_owner_cap  = 
                test_scenario::take_from_sender<ShopOwnerCapability>(scenario);
            let shop = test_scenario::take_shared<Shop>(scenario);

            add_item(
                &mut shop, 
                &shop_owner_cap,
                b"title", 
                b"description", 
                b"url", 
                1000000000, // 1 SUI
                34, 
                3
            );

            test_scenario::return_to_sender(scenario, shop_owner_cap);
            test_scenario::return_shared(shop);
        };
        let tx = test_scenario::next_tx(scenario, buyer);
        let expected_events_emitted = 1;
        assert_eq(
            test_scenario::num_user_events(&tx),
            expected_events_emitted
        );

        {
            let shop = test_scenario::take_shared<Shop>(scenario);
            let item_id = 0;
            let item_ref = vector::borrow(&shop.items, item_id);

            let price = item_ref.price;
            let quantity_to_buy = 1;

            let payment_coin = sui::coin::mint_for_testing<SUI>(
                price * quantity_to_buy, 
                test_scenario::ctx(scenario)
            );

            purchase_item(
                &mut shop, 
                item_ref.id, 
                quantity_to_buy, 
                buyer, 
                &mut payment_coin, 
                test_scenario::ctx(scenario)
            );

            test_scenario::return_shared(shop);

            coin::destroy_zero(payment_coin);
        };
        let tx = test_scenario::next_tx(scenario, buyer);
        let expected_events_emitted = 1;
        assert_eq(
            test_scenario::num_user_events(&tx),
            expected_events_emitted
        );

        {
            let shop = test_scenario::take_shared<Shop>(scenario);
            let item_id = 0;
            let item_ref = vector::borrow(&shop.items, item_id);

            let price = item_ref.price;
            let quantity_to_buy = 1;

            let payment_coin = sui::coin::mint_for_testing<SUI>(
                price * quantity_to_buy + 1, 
                test_scenario::ctx(scenario)
            );

            purchase_item(
                &mut shop, 
                item_ref.id, 
                quantity_to_buy, 
                buyer, 
                &mut payment_coin, 
                test_scenario::ctx(scenario)
            );

            test_scenario::return_shared(shop);

            transfer::public_transfer(payment_coin, @0x0);
        };
        let tx = test_scenario::next_tx(scenario, buyer);
        let expected_events_emitted = 1;
        assert_eq(
            test_scenario::num_user_events(&tx),
            expected_events_emitted
        );

        {
            let shop = test_scenario::take_shared<Shop>(scenario);
            let item_id = 0;
            let item_ref = vector::borrow(&shop.items, item_id);

            let price = item_ref.price;
            let quantity_to_buy = 1;

            let payment_coin = sui::coin::mint_for_testing<SUI>(
                price, 
                test_scenario::ctx(scenario)
            );

            purchase_item(
                &mut shop, 
                item_ref.id, 
                quantity_to_buy, 
                buyer, 
                &mut payment_coin, 
                test_scenario::ctx(scenario)
            );

            test_scenario::return_shared(shop);

            coin::destroy_zero(payment_coin);
        };
        let tx = test_scenario::next_tx(scenario, buyer);
        let expected_events_emitted = 1;
        assert_eq(
            test_scenario::num_user_events(&tx),
            expected_events_emitted
        );

        {
            let shop = test_scenario::take_shared<Shop>(scenario);
            let item_id = 0;
            let item_ref = vector::borrow(&shop.items, item_id);

            let expected_purchase_quantity = 3;
            let expected_supply = 34;

            assert_eq(item_ref.available, expected_supply - expected_purchase_quantity);
            assert_eq(balance::value(&shop.balance), item_ref.price * expected_purchase_quantity);
            assert_eq(item_ref.listed, true);

            let purchased_item = test_scenario::take_from_sender<PurchasedItem>(scenario);
            assert_eq(purchased_item.item_id, item_ref.id);

            assert_eq(
                vector::length(&test_scenario::ids_for_sender<PurchasedItem>(scenario)), 
                3
            );

            test_scenario::return_shared(shop);
            test_scenario::return_to_sender(scenario, purchased_item);
        };
        test_scenario::end(scenario_val);
    }

    #[test]
    public fun test_purchase_item_success_purchase_one_item_multiple_quantity() {
        let shop_owner = @0xa;
        let buyer = @0xb;

        let scenario_val = test_scenario::begin(shop_owner);
        let scenario = &mut scenario_val;

        {
            create_shop(shop_owner, test_scenario::ctx(scenario));
        };
        test_scenario::next_tx(scenario, shop_owner);

        {
            let shop_owner_cap  = 
                test_scenario::take_from_sender<ShopOwnerCapability>(scenario);
            let shop = test_scenario::take_shared<Shop>(scenario);

            add_item(
                &mut shop, 
                &shop_owner_cap,
                b"title", 
                b"description", 
                b"url", 
                1000000000, // 1 SUI
                34, 
                3
            );

            test_scenario::return_to_sender(scenario, shop_owner_cap);
            test_scenario::return_shared(shop);
        };
        test_scenario::next_tx(scenario, buyer);

        {
            let shop = test_scenario::take_shared<Shop>(scenario);
            let item_id = 0;
            let item_ref = vector::borrow(&shop.items, item_id);

            let price = item_ref.price;

            let quantity_to_buy = 5;

            let payment_coin = sui::coin::mint_for_testing<SUI>(
                price * quantity_to_buy, 
                test_scenario::ctx(scenario)
            );

            purchase_item(
                &mut shop, 
                item_ref.id, 
                quantity_to_buy, 
                buyer, 
                &mut payment_coin, 
                test_scenario::ctx(scenario)
            );

            test_scenario::return_shared(shop);

            coin::destroy_zero(payment_coin);
        };
        let tx = test_scenario::next_tx(scenario, buyer);
        let expected_events_emitted = 1;
        assert_eq(
            test_scenario::num_user_events(&tx),
            expected_events_emitted
        );

        {
            let expected_quantity_purchased = 5;
            let expected_supply = 34;

            let shop = test_scenario::take_shared<Shop>(scenario);
            let item_id = 0;
            let item_ref = vector::borrow(&shop.items, item_id);
            assert_eq(item_ref.available, expected_supply - expected_quantity_purchased);
            assert_eq(balance::value(&shop.balance), item_ref.price * expected_quantity_purchased);
            assert_eq(item_ref.listed, true);

            let purchased_item = test_scenario::take_from_sender<PurchasedItem>(scenario);
            assert_eq(purchased_item.item_id, item_ref.id);

            assert_eq(
                vector::length(&test_scenario::ids_for_sender<PurchasedItem>(scenario)), 
                5
            );

            test_scenario::return_shared(shop);
            test_scenario::return_to_sender(scenario, purchased_item);
        };
        let tx = test_scenario::end(scenario_val);
        let expected_events_emitted = 0;
        assert_eq(
            test_scenario::num_user_events(&tx),
            expected_events_emitted
        );
    }

    #[test, expected_failure(abort_code = EItemIsNotListed)]
    public fun test_purchase_item_failure_item_is_unlisted() {
        let shop_owner = @0xa;
        let buyer = @0xb;

        let scenario_val = test_scenario::begin(shop_owner);
        let scenario = &mut scenario_val;

        {
            create_shop(shop_owner, test_scenario::ctx(scenario));
        };
        test_scenario::next_tx(scenario, shop_owner);

        {
            let shop_owner_cap  = 
                test_scenario::take_from_sender<ShopOwnerCapability>(scenario);
            let shop = test_scenario::take_shared<Shop>(scenario);

            add_item(
                &mut shop, 
                &shop_owner_cap,
                b"title", 
                b"description", 
                b"url", 
                1000000000, // 1 SUI
                34, 
                3
            );

            test_scenario::return_to_sender(scenario, shop_owner_cap);
            test_scenario::return_shared(shop);
        };
        test_scenario::next_tx(scenario, shop_owner);

        {
            let shop_owner_cap  = 
                test_scenario::take_from_sender<ShopOwnerCapability>(scenario);
            let shop = test_scenario::take_shared<Shop>(scenario);
            let item_id = 0;
            let item_ref = vector::borrow(&shop.items, item_id);

            unlist_item(
                &mut shop, 
                &shop_owner_cap,
                item_ref.id
            );

            test_scenario::return_to_sender(scenario, shop_owner_cap);
            test_scenario::return_shared(shop);
        };
        test_scenario::next_tx(scenario, buyer);

        {
            let shop = test_scenario::take_shared<Shop>(scenario);
            let item_id = 0;
            let item_ref = vector::borrow(&shop.items, item_id);

            let price = item_ref.price;
            let quantity_to_buy = 1;

            let payment_coin = sui::coin::mint_for_testing<SUI>(
                price * quantity_to_buy, 
                test_scenario::ctx(scenario)
            );

            purchase_item(
                &mut shop, 
                item_ref.id, 
                quantity_to_buy, 
                buyer, 
                &mut payment_coin, 
                test_scenario::ctx(scenario)
            );

            test_scenario::return_shared(shop);

            coin::destroy_zero(payment_coin);
        };
        test_scenario::next_tx(scenario, buyer);

        {
            let shop = test_scenario::take_shared<Shop>(scenario);
            let item_id = 0;
            let item_ref = vector::borrow(&shop.items, item_id);

            let expected_total_supply = 34;
            let expected_quantity_purchased = 1;

            assert_eq(item_ref.available, expected_total_supply - expected_quantity_purchased);
            assert_eq(balance::value(&shop.balance), item_ref.price);
            assert_eq(item_ref.listed, true);

            let purchased_item = test_scenario::take_from_sender<PurchasedItem>(scenario);
            assert_eq(purchased_item.item_id, item_ref.id);

            test_scenario::return_shared(shop);
            test_scenario::return_to_sender(scenario, purchased_item);
        };
        test_scenario::end(scenario_val);
    }

    #[test, expected_failure(abort_code = EInsufficientPayment)]
    public fun test_purchase_item_failure_insufficient_payment() {
        let shop_owner = @0xa;
        let buyer = @0xb;

        let scenario_val = test_scenario::begin(shop_owner);
        let scenario = &mut scenario_val;

        {
            create_shop(shop_owner, test_scenario::ctx(scenario));
        };
        test_scenario::next_tx(scenario, shop_owner);

        {
            let shop_owner_cap  = 
                test_scenario::take_from_sender<ShopOwnerCapability>(scenario);
            let shop = test_scenario::take_shared<Shop>(scenario);

            add_item(
                &mut shop, 
                &shop_owner_cap,
                b"title", 
                b"description", 
                b"url", 
                1000000000, // 1 SUI
                34, 
                3
            );

            test_scenario::return_to_sender(scenario, shop_owner_cap);
            test_scenario::return_shared(shop);
        };
        test_scenario::next_tx(scenario, buyer);

        {
            let shop = test_scenario::take_shared<Shop>(scenario);
            let item_id = 0;
            let item_ref = vector::borrow(&shop.items, item_id);

            let price = item_ref.price;
            let quantity_to_buy = 1;

            let payment_coin = sui::coin::mint_for_testing<SUI>(
                price * quantity_to_buy - 1, 
                test_scenario::ctx(scenario)
            );

            purchase_item(
                &mut shop, 
                item_ref.id, 
                quantity_to_buy, 
                buyer, 
                &mut payment_coin, 
                test_scenario::ctx(scenario)
            );

            test_scenario::return_shared(shop);

            coin::destroy_zero(payment_coin);
        };
        test_scenario::end(scenario_val);
    }

    #[test, expected_failure(abort_code = EInvalidQuantity)]
    public fun test_purchase_item_failure_quantity_over_available_amount() {
        let shop_owner = @0xa;
        let buyer = @0xb;

        let scenario_val = test_scenario::begin(shop_owner);
        let scenario = &mut scenario_val;

        {
            create_shop(shop_owner, test_scenario::ctx(scenario));
        };
        test_scenario::next_tx(scenario, shop_owner);

        {
            let shop_owner_cap  = 
                test_scenario::take_from_sender<ShopOwnerCapability>(scenario);
            let shop = test_scenario::take_shared<Shop>(scenario);

            add_item(
                &mut shop, 
                &shop_owner_cap,
                b"title", 
                b"description", 
                b"url", 
                1000000000, // 1 SUI
                34, 
                3
            );

            test_scenario::return_to_sender(scenario, shop_owner_cap);
            test_scenario::return_shared(shop);
        };
        test_scenario::next_tx(scenario, buyer);

        {
            let shop = test_scenario::take_shared<Shop>(scenario);
            let item_id = 0;
            let item_ref = vector::borrow(&shop.items, item_id);

            let price = item_ref.price;

            let payment_coin = sui::coin::mint_for_testing<SUI>(
                price, 
                test_scenario::ctx(scenario)
            );

            let quantityPlusOne = item_ref.available + 1;

            purchase_item(
                &mut shop, 
                item_ref.id, 
                quantityPlusOne, 
                buyer, 
                &mut payment_coin, 
                test_scenario::ctx(scenario)
            );

            test_scenario::return_shared(shop);

            coin::destroy_zero(payment_coin);
        };
        test_scenario::end(scenario_val);
    }

    #[test]
    public fun test_unlist_item_success_unlist_item_with_no_purchases() {
        let shop_owner = @0xa;

        let scenario_val = test_scenario::begin(shop_owner);
        let scenario = &mut scenario_val;

        {
            create_shop(shop_owner, test_scenario::ctx(scenario));
        };
        test_scenario::next_tx(scenario, shop_owner);

        {
            let shop_owner_cap  = 
                test_scenario::take_from_sender<ShopOwnerCapability>(scenario);
            let shop = test_scenario::take_shared<Shop>(scenario);

            add_item(
                &mut shop, 
                &shop_owner_cap,
                b"title", 
                b"description", 
                b"url", 
                1000000000, // 1 SUI
                34, 
                3
            );

            test_scenario::return_to_sender(scenario, shop_owner_cap);
            test_scenario::return_shared(shop);
        };
        test_scenario::next_tx(scenario, shop_owner);

        {
            let shop_owner_cap  = 
                test_scenario::take_from_sender<ShopOwnerCapability>(scenario);
            let shop = test_scenario::take_shared<Shop>(scenario);
            let item_id = 0;
            let item_ref = vector::borrow(&shop.items, item_id);

            unlist_item(
                &mut shop, 
                &shop_owner_cap,
                item_ref.id
            );

            test_scenario::return_to_sender(scenario, shop_owner_cap);
            test_scenario::return_shared(shop);
        };
        let tx = test_scenario::next_tx(scenario, shop_owner);
        let expected_events_emitted = 1;
        assert_eq(
            test_scenario::num_user_events(&tx),
            expected_events_emitted
        );

        {
            let shop = test_scenario::take_shared<Shop>(scenario);
            let item_id = 0;
            let item_ref = vector::borrow(&shop.items, item_id);
            assert_eq(item_ref.listed, false);

            test_scenario::return_shared(shop);
        };
        let tx = test_scenario::end(scenario_val);
        let expected_events_emitted = 0;
        assert_eq(
            test_scenario::num_user_events(&tx),
            expected_events_emitted
        );
    }

    #[test]
    public fun test_unlist_item_success_unlist_item_with_some_purchases() {
        let shop_owner = @0xa;
        let buyer1 = @0xb;
        let buyer2 = @0xc;

        let scenario_val = test_scenario::begin(shop_owner);
        let scenario = &mut scenario_val;
        {
            create_shop(shop_owner, test_scenario::ctx(scenario));
        };

        test_scenario::next_tx(scenario, shop_owner);
        {
            let shop_owner_cap  = 
                test_scenario::take_from_sender<ShopOwnerCapability>(scenario);
            let shop = test_scenario::take_shared<Shop>(scenario);

            add_item(
                &mut shop, 
                &shop_owner_cap,
                b"title", 
                b"description", 
                b"url", 
                1000000000, // 1 SUI
                34, 
                3
            );

            test_scenario::return_to_sender(scenario, shop_owner_cap);
            test_scenario::return_shared(shop);
        };

        test_scenario::next_tx(scenario, buyer1);
        {
            let shop = test_scenario::take_shared<Shop>(scenario);
            let item_id = 0;
            let item_ref = vector::borrow(&shop.items, item_id);

            let price = item_ref.price;

            let payment_coin = sui::coin::mint_for_testing<SUI>(
                price, 
                test_scenario::ctx(scenario)
            );

            purchase_item(
                &mut shop, 
                item_ref.id, 
                1, 
                buyer1, 
                &mut payment_coin, 
                test_scenario::ctx(scenario)
            );

            test_scenario::return_shared(shop);

            coin::destroy_zero(payment_coin);
        };

        test_scenario::next_tx(scenario, buyer2);
        {
            let shop = test_scenario::take_shared<Shop>(scenario);
            let item_id = 0;
            let item_ref = vector::borrow(&shop.items, item_id);

            let quantity_to_buy = 8;

            let price = item_ref.price * quantity_to_buy;

            let payment_coin = sui::coin::mint_for_testing<SUI>(
                price, 
                test_scenario::ctx(scenario)
            );

            purchase_item(
                &mut shop, 
                item_ref.id, 
                quantity_to_buy, 
                buyer2, 
                &mut payment_coin, 
                test_scenario::ctx(scenario)
            );

            test_scenario::return_shared(shop);

            coin::destroy_zero(payment_coin);
        };

        test_scenario::next_tx(scenario, shop_owner);
        {
            let shop_owner_cap  = 
                test_scenario::take_from_sender<ShopOwnerCapability>(scenario);
            let shop = test_scenario::take_shared<Shop>(scenario);
            let item_id = 0;
            let item_ref = vector::borrow(&shop.items, item_id);

            unlist_item(
                &mut shop, 
                &shop_owner_cap,
                item_ref.id
            );

            test_scenario::return_to_sender(scenario, shop_owner_cap);
            test_scenario::return_shared(shop);
        };

        let tx = test_scenario::next_tx(scenario, shop_owner);
        let expected_events_emitted = 1;
        assert_eq(
            test_scenario::num_user_events(&tx),
            expected_events_emitted
        );

        {
            let shop = test_scenario::take_shared<Shop>(scenario);
            let item_id = 0;
            let item_ref = vector::borrow(&shop.items, item_id);

            let expected_total_supply = 34;
            let expected_quantity_purchased = 9;

            assert_eq(item_ref.listed, false);
            assert_eq(item_ref.available, expected_total_supply - expected_quantity_purchased);

            test_scenario::return_shared(shop);
        };

        let tx = test_scenario::end(scenario_val);
        let expected_events_emitted = 0;
        assert_eq(
            test_scenario::num_user_events(&tx),
            expected_events_emitted
        );
    }

    #[test, expected_failure(abort_code = ENotShopOwner)]
    public fun test_unlist_item_failure_wrong_shop_owner_cap() {
        let user1 = @0xa;
        let user2 = @0xb;

        let scenario_val = test_scenario::begin(user1);
        let scenario = &mut scenario_val;

        {
            create_shop(user2, test_scenario::ctx(scenario));
            create_shop(user1, test_scenario::ctx(scenario));
        };
        test_scenario::next_tx(scenario, user1);

        {
            let shop_owner_cap_of_user_1  = 
                test_scenario::take_from_sender<ShopOwnerCapability>(scenario);
            let shop_of_user_1 = test_scenario::take_shared<Shop>(scenario);
            
            add_item(
                &mut shop_of_user_1, 
                &shop_owner_cap_of_user_1,
                b"title", 
                b"description", 
                b"url", 
                1000000000, // 1 SUI
                34, 
                3
            );

            test_scenario::return_to_sender(scenario, shop_owner_cap_of_user_1);
            test_scenario::return_shared(shop_of_user_1);
        };
        test_scenario::next_tx(scenario, user2);

        {
            let shop_owner_cap_of_user_2  = 
                test_scenario::take_from_sender<ShopOwnerCapability>(scenario);
            let shop_of_user_1 = test_scenario::take_shared<Shop>(scenario);
            let item_id = 0;
            let item_ref = vector::borrow(&shop_of_user_1.items, item_id);

            unlist_item(
                &mut shop_of_user_1, 
                &shop_owner_cap_of_user_2,
                item_ref.id
            );

            test_scenario::return_to_sender(scenario, shop_owner_cap_of_user_2);
            test_scenario::return_shared(shop_of_user_1);
        };
        test_scenario::end(scenario_val);
    }

    #[test]
    public fun test_withdraw_from_shop_success_withdraw_full_balance() {
        let shop_owner = @0xa;
        let buyer = @0xb;
        let recipient = @0xc;

        let scenario_val = test_scenario::begin(shop_owner);
        let scenario = &mut scenario_val;

        {
            create_shop(shop_owner, test_scenario::ctx(scenario));
        };
        test_scenario::next_tx(scenario, shop_owner);

        {
            let shop_owner_cap  = 
                test_scenario::take_from_sender<ShopOwnerCapability>(scenario);
            let shop = test_scenario::take_shared<Shop>(scenario);

            add_item(
                &mut shop, 
                &shop_owner_cap,
                b"title", 
                b"description", 
                b"url", 
                1000000000, // 1 SUI
                34, 
                3
            );

            test_scenario::return_to_sender(scenario, shop_owner_cap);
            test_scenario::return_shared(shop);
        };
        test_scenario::next_tx(scenario, buyer);

        {
            let shop = test_scenario::take_shared<Shop>(scenario);
            let item_id = 0;
            let item_ref = vector::borrow(&shop.items, item_id);

            let price = item_ref.price;

            let payment_coin = sui::coin::mint_for_testing<SUI>(
                price, 
                test_scenario::ctx(scenario)
            );

            purchase_item(
                &mut shop, 
                item_ref.id, 
                1, 
                buyer, 
                &mut payment_coin, 
                test_scenario::ctx(scenario)
            );

            test_scenario::return_shared(shop);

            coin::destroy_zero(payment_coin);
        };
        test_scenario::next_tx(scenario, shop_owner);

        {
            let shop_owner_cap  = 
                test_scenario::take_from_sender<ShopOwnerCapability>(scenario);
            let shop = test_scenario::take_shared<Shop>(scenario);

            let withdrawal_amount = balance::value(&shop.balance);

            withdraw_from_shop(
                &mut shop, 
                &shop_owner_cap,
                withdrawal_amount,
                recipient,
                test_scenario::ctx(scenario)
            );

            test_scenario::return_to_sender(scenario, shop_owner_cap);
            test_scenario::return_shared(shop);
        };

        let tx = test_scenario::next_tx(scenario, shop_owner);
        let expected_events_emitted = 1;
        assert_eq(
            test_scenario::num_user_events(&tx),
            expected_events_emitted
        );

        {
            let expected_shop_balance = 0;
            let shop = test_scenario::take_shared<Shop>(scenario);
            assert_eq(balance::value(&shop.balance), expected_shop_balance);

            test_scenario::return_shared(shop);
        };

        test_scenario::next_tx(scenario, recipient);
        {

            let expected_amount = 1000000000;
            let coin = test_scenario::take_from_sender<coin::Coin<SUI>>(scenario);
            assert_eq(coin::value(&coin), expected_amount);

            test_scenario::return_to_sender(scenario, coin);
        };
        test_scenario::end(scenario_val);

    }

    #[test]
    public fun test_withdraw_from_shop_success_withdraw_partial_balance() {
        let shop_owner = @0xa;
        let buyer = @0xb;
        let recipient = @0xc;

        let scenario_val = test_scenario::begin(shop_owner);
        let scenario = &mut scenario_val;

        {
            create_shop(shop_owner, test_scenario::ctx(scenario));
        };
        test_scenario::next_tx(scenario, shop_owner);

        {
            let shop_owner_cap  = 
                test_scenario::take_from_sender<ShopOwnerCapability>(scenario);
            let shop = test_scenario::take_shared<Shop>(scenario);

            add_item(
                &mut shop, 
                &shop_owner_cap,
                b"title", 
                b"description", 
                b"url", 
                1000000000, // 1 SUI
                34, 
                3
            );

            test_scenario::return_to_sender(scenario, shop_owner_cap);
            test_scenario::return_shared(shop);
        };
        test_scenario::next_tx(scenario, buyer);

        {
            let shop = test_scenario::take_shared<Shop>(scenario);
            let item_id = 0;
            let item_ref = vector::borrow(&shop.items, item_id);

            let price = item_ref.price;

            let payment_coin = sui::coin::mint_for_testing<SUI>(
                price, 
                test_scenario::ctx(scenario)
            );

            purchase_item(
                &mut shop, 
                item_ref.id, 
                1, 
                buyer, 
                &mut payment_coin, 
                test_scenario::ctx(scenario)
            );

            test_scenario::return_shared(shop);

            coin::destroy_zero(payment_coin);
        };
        test_scenario::next_tx(scenario, shop_owner);

        {
            let shop_owner_cap  = 
                test_scenario::take_from_sender<ShopOwnerCapability>(scenario);
            let shop = test_scenario::take_shared<Shop>(scenario);

            let withdrawal_amount = balance::value(&shop.balance);

            withdraw_from_shop(
                &mut shop, 
                &shop_owner_cap,
                withdrawal_amount / 2,
                recipient,
                test_scenario::ctx(scenario)
            );

            test_scenario::return_to_sender(scenario, shop_owner_cap);
            test_scenario::return_shared(shop);
        };

        let tx = test_scenario::next_tx(scenario, shop_owner);
        let expected_events_emitted = 1;
        assert_eq(
            test_scenario::num_user_events(&tx),
            expected_events_emitted
        );

        {
            let expected_amount_left_over = 500000000;
            let shop = test_scenario::take_shared<Shop>(scenario);
            assert_eq(
                balance::value(&shop.balance), expected_amount_left_over
            );

            test_scenario::return_shared(shop);
        };

        test_scenario::next_tx(scenario, recipient);
        {

            let expected_amount = 500000000;
            let coin = test_scenario::take_from_sender<coin::Coin<SUI>>(scenario);
            assert_eq(coin::value(&coin), expected_amount);

            test_scenario::return_to_sender(scenario, coin);
        };
        test_scenario::end(scenario_val);
    }

    #[test, expected_failure(abort_code = ENotShopOwner)]
    public fun test_withdraw_from_shop_failure_wrong_shop_owner_cap() {
        let user1 = @0xa;
        let user2 = @0xb;

        let scenario_val = test_scenario::begin(user1);
        let scenario = &mut scenario_val;

        {
            create_shop(user2, test_scenario::ctx(scenario));
            create_shop(user1, test_scenario::ctx(scenario));
        };
        test_scenario::next_tx(scenario, user1);

        {
            let shop_owner_cap_of_user_1  = 
                test_scenario::take_from_sender<ShopOwnerCapability>(scenario);
            let shop_of_user_1 = test_scenario::take_shared<Shop>(scenario);
            
            add_item(
                &mut shop_of_user_1, 
                &shop_owner_cap_of_user_1,
                b"title", 
                b"description", 
                b"url", 
                1000000000, // 1 SUI
                34, 
                3
            );

            test_scenario::return_to_sender(scenario, shop_owner_cap_of_user_1);
            test_scenario::return_shared(shop_of_user_1);
        };
        test_scenario::next_tx(scenario, user2);

        {
            let shop_of_user_1 = test_scenario::take_shared<Shop>(scenario);

            let item_id = 0;
            let item_ref = vector::borrow(&shop_of_user_1.items, item_id);
            let price = item_ref.price;

            let payment_coin = coin::mint_for_testing<SUI>(
                price, 
                test_scenario::ctx(scenario)
            );

            purchase_item(
                &mut shop_of_user_1, 
                item_ref.id, 
                1, 
                user2, 
                &mut payment_coin, 
                test_scenario::ctx(scenario)
            );

            test_scenario::return_shared(shop_of_user_1);
            coin::destroy_zero(payment_coin);
        };
        test_scenario::next_tx(scenario, user2);

        {
            let shop_owner_cap_of_user_2  = 
                test_scenario::take_from_sender<ShopOwnerCapability>(scenario);
            let shop_of_user_1 = test_scenario::take_shared<Shop>(scenario);

            withdraw_from_shop(
                &mut shop_of_user_1, 
                &shop_owner_cap_of_user_2,
                1000000000,
                user1,
                test_scenario::ctx(scenario)
            );

            test_scenario::return_to_sender(scenario, shop_owner_cap_of_user_2);
            test_scenario::return_shared(shop_of_user_1);
        };
        test_scenario::end(scenario_val);
    }

    #[test, expected_failure(abort_code = EInvalidWithdrawalAmount)]
    public fun test_withdraw_from_shop_failure_amount_greater_than_balance() {
        let shop_owner = @0xa;
        let buyer = @0xb;
        let recipient = @0xc;

        let scenario_val = test_scenario::begin(shop_owner);
        let scenario = &mut scenario_val;

        {
            create_shop(shop_owner, test_scenario::ctx(scenario));
        };
        test_scenario::next_tx(scenario, shop_owner);

        {
            let shop_owner_cap  = 
                test_scenario::take_from_sender<ShopOwnerCapability>(scenario);
            let shop = test_scenario::take_shared<Shop>(scenario);

            add_item(
                &mut shop, 
                &shop_owner_cap,
                b"title", 
                b"description", 
                b"url", 
                1000000000, // 1 SUI
                34, 
                3
            );

            test_scenario::return_to_sender(scenario, shop_owner_cap);
            test_scenario::return_shared(shop);
        };
        test_scenario::next_tx(scenario, buyer);

        {
            let shop = test_scenario::take_shared<Shop>(scenario);
            let item_id = 0;
            let item_ref = vector::borrow(&shop.items, item_id);

            let price = item_ref.price;
            let quantity_to_buy = 1;

            let payment_coin = sui::coin::mint_for_testing<SUI>(
                price, 
                test_scenario::ctx(scenario)
            );

            purchase_item(
                &mut shop, 
                item_ref.id, 
                quantity_to_buy, 
                buyer, 
                &mut payment_coin, 
                test_scenario::ctx(scenario)
            );

            test_scenario::return_shared(shop);

            coin::destroy_zero(payment_coin);
        };
        test_scenario::next_tx(scenario, shop_owner);

        {
            let shop_owner_cap  = 
                test_scenario::take_from_sender<ShopOwnerCapability>(scenario);
            let shop = test_scenario::take_shared<Shop>(scenario);

            let withdrawal_amount = balance::value(&shop.balance);

            withdraw_from_shop(
                &mut shop, 
                &shop_owner_cap,
                withdrawal_amount + 1,
                recipient,
                test_scenario::ctx(scenario)
            );

            test_scenario::return_to_sender(scenario, shop_owner_cap);
            test_scenario::return_shared(shop);
        };
        test_scenario::end(scenario_val);

    }
}
