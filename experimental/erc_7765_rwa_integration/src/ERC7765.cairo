
#[starknet::contract]
mod ERC7765Contract {
    
    use core::num::traits::Zero;
    use starknet::{ContractAddress, get_caller_address};    
    use starknet::event::EventEmitter;
    use erc_7765_rwa_integration::interfaces::IERC7765::{IERC7765, IERC7765Metadata};
    use alexandria_storage::list::{List, ListTrait};
    use starknet::storage::{StoragePointerReadAccess, StoragePointerWriteAccess, StorageMapReadAccess, StorageMapWriteAccess};

    #[storage]
    struct Storage {
        ERC7765_creator: ContractAddress,
        ERC7765_name: ByteArray,
        ERC7765_symbol: ByteArray,
        ERC7765_owners: LegacyMap<u256, ContractAddress>,
        ERC7765_balances: LegacyMap<ContractAddress, u256>,
        ERC7765_token_approvals: LegacyMap<u256, ContractAddress>,
        ERC7765_operator_approvals: LegacyMap<(ContractAddress, ContractAddress), bool>,
        ERC7765_base_uri: ByteArray,
        ERC7765_privileges_index: LegacyMap<u32, u256>,
        ERC7765_privileges_to_index: LegacyMap<u256, u32>,
        ERC7765_privilege_exercised: LegacyMap<(u256, u256), bool>,
        ERC7765_privileges: List<u256>
    }
    
    #[event]
    #[derive(Drop, PartialEq, starknet::Event)]
    pub enum Event {
        Transfer: Transfer,
        Approval: Approval,
        ApprovalForAll: ApprovalForAll,
        PrivilegeExercised: PrivilegeExercised,
    }

    /// Emitted when `token_id` token is transferred from `from` to `to`.
    #[derive(Drop, PartialEq, starknet::Event)]
    pub struct Transfer {
        #[key]
        pub from: ContractAddress,
        #[key]
        pub to: ContractAddress,
        #[key]
        pub token_id: u256
    }

    /// Emitted when `owner` enables `approved` to manage the `token_id` token.
    #[derive(Drop, PartialEq, starknet::Event)]
    pub struct Approval {
        #[key]
        pub owner: ContractAddress,
        #[key]
        pub approved: ContractAddress,
        #[key]
        pub token_id: u256
    }

    /// Emitted when `owner` enables or disables (`approved`) `operator` to manage
    /// all of its assets.
    #[derive(Drop, PartialEq, starknet::Event)]
    pub struct ApprovalForAll {
        #[key]
        pub owner: ContractAddress,
        #[key]
        pub operator: ContractAddress,
        pub approved: bool
    }

    #[derive(Drop, PartialEq, starknet::Event)]
    pub struct PrivilegeExercised {
        #[key]
        pub to: ContractAddress,
        #[key]
        pub operator: ContractAddress,
        pub token_id: u256, 
        pub privilege_id: u256
    }


    #[constructor]
    fn constructor(
        ref self: ContractState,
        creator: ContractAddress,
        name: ByteArray,
        symbol: ByteArray,
        token_base_uri: ByteArray,
        privilege_ids: Array<u256>
    ) {
            self.ERC7765_creator.write(creator);
            self.ERC7765_name.write(name);
            self.ERC7765_symbol.write(symbol);
            self.ERC7765_base_uri.write(token_base_uri);


            let mut privileges = self.ERC7765_privileges.read();
            privileges.from_array(@privilege_ids);
            self.ERC7765_privileges.write(privileges);


            let privileges_len = privilege_ids.len().try_into().unwrap();
            let mut i: u32 = 1;
            loop {
                if i > privileges_len {
                    break;
                }

                self.ERC7765_privileges_index.write(i, *privilege_ids.at(i));
                self.ERC7765_privileges_to_index.write(*privilege_ids.at(i), i);
                i +=1;
            };
    }
    

    #[abi(embed_v0)]
    impl ERC7765Metadata of IERC7765Metadata<ContractState> {
        
        fn name(self: @ContractState) -> ByteArray {
            self.ERC7765_name.read()
        }

        fn symbol(self: @ContractState) -> ByteArray {
            self.ERC7765_symbol.read()
        }
        fn token_uri(self: @ContractState, token_id: u256) -> ByteArray {
            self.ERC7765_base_uri.read()
        }
    
        // Specific to ERC7765

        // TODO
        fn privilegeURI(self: @ContractState, privilege_id: u256) -> ByteArray{
            self.ERC7765_symbol.read()
        }
    }
    #[abi(embed_v0)]
    impl ERC7765 of IERC7765<ContractState> {

        fn balance_of(self: @ContractState, account: ContractAddress) -> u256 {
            self._assert_valid_account(account);
            self.ERC7765_balances.read(account)
        }
        
        fn owner_of(self: @ContractState, token_id: u256) -> ContractAddress {
            self._owner_of(token_id)
        }

        fn safe_transfer_from(
            ref self: ContractState,
            from: ContractAddress,
            to: ContractAddress,
            token_id: u256,
            data: Span<felt252>
        ) {
            self._assert_authorized(token_id);
            self._safe_transfer(from, to, token_id, data);
        }

        fn transfer_from(
            ref self: ContractState,
            from: ContractAddress,
            to: ContractAddress,
            token_id: u256
        ) {
            self._assert_authorized(token_id);
            self._transfer(from, to, token_id);
        }

        fn approve(ref self: ContractState, to: ContractAddress, token_id: u256) {
            let owner = self._owner_of(token_id);

            let caller = get_caller_address();
            assert(
                owner == caller || self.is_approved_for_all(owner, caller), 'Unauthorized'
            );
            self._approve(to, token_id);
        }

        fn set_approval_for_all(
            ref self: ContractState, operator: ContractAddress, approved: bool
        ) {
            self._set_approval_for_all(get_caller_address(), operator, approved)
        }

        fn get_approved(self: @ContractState, token_id: u256) -> ContractAddress {
            self.assert_token_exists(token_id);
            self.ERC7765_token_approvals.read(token_id)
        }

        /// Query if `operator` is an authorized operator for `owner`.
        fn is_approved_for_all(
            self: @ContractState, owner: ContractAddress, operator: ContractAddress
        ) -> bool {
            self.ERC7765_operator_approvals.read((owner, operator))
        }
    
        // // Specific to ERC7765

        fn is_exercisable(self: @ContractState, token_id: u256, privilege_id: u256, ) -> bool {
            !self.is_exercised(token_id, privilege_id)
        }

        fn is_exercised(self: @ContractState,  token_id: u256, privilege_id: u256, ) -> bool {
            self.ERC7765_privilege_exercised.read((token_id, privilege_id))
        }

        fn get_privilege_ids(self: @ContractState, token_id: u256) -> Array<u256> {
            self.ERC7765_privileges.read().array()
        }

        fn exercise_privilege(ref self: ContractState, token_id: u256, to: ContractAddress, privilege_id: u256) {

            self._assert_owner(token_id);
            self._assert_privilege_exists(privilege_id);
            self.ERC7765_privilege_exercised.write((token_id, privilege_id), true);
            self.emit(PrivilegeExercised { to,  operator: to, token_id, privilege_id} );

        }
    }

    #[generate_trait]
    impl InternalImpl of InternalImplTrait {

        fn _owner_of(self: @ContractState, token_id: u256) -> ContractAddress {
            let owner = self.ERC7765_owners.read(token_id);
            assert(!owner.is_zero(), 'Invalid token Id');
            owner
        }

        fn _is_approved_or_owner(
            self: @ContractState, spender: ContractAddress, token_id: u256
        ) -> bool {
            let owner = self._owner_of(token_id);
            let is_approved_for_all = self.is_approved_for_all(owner, spender);
            owner == spender || is_approved_for_all || spender == self.get_approved(token_id)
        }

        fn _approve(ref self: ContractState, to: ContractAddress, token_id: u256) {
            let owner = self._owner_of(token_id);
            assert(owner != to, 'Cant approve owner');

            self.ERC7765_token_approvals.write(token_id, to);
            self.emit(Approval { owner, approved: to, token_id });
        }

        fn _exists(self: @ContractState, token_id: u256) -> bool {
            !self.ERC7765_owners.read(token_id).is_zero()
        }

        fn _set_approval_for_all(
            ref self: ContractState,
            owner: ContractAddress,
            operator: ContractAddress,
            approved: bool
        ) {
            assert(owner != operator, 'Self approval');
            self.ERC7765_operator_approvals.write((owner, operator), approved);
            self.emit(ApprovalForAll { owner, operator, approved });
        }

        fn _transfer(
            ref self: ContractState,
            from: ContractAddress,
            to: ContractAddress,
            token_id: u256
        ) {
            assert(!to.is_zero(), 'Invalid receiver');
            let owner = self._owner_of(token_id);
            assert(from == owner, 'Wrong sender');

            // Implicit clear approvals, no need to emit an event
            // self.ERC7765_token_approvals.write(token_id, ContractAddress(0));

            self.ERC7765_balances.write(from, self.ERC7765_balances.read(from) - 1);
            self.ERC7765_balances.write(to, self.ERC7765_balances.read(to) + 1);
            self.ERC7765_owners.write(token_id, to);

            self.emit(Transfer { from, to, token_id });
        }

        fn _safe_transfer(
            ref self: ContractState,
            from: ContractAddress,
            to: ContractAddress,
            token_id: u256,
            data: Span<felt252>
        ) {
            self._transfer(from, to, token_id);
            // assert(
            //     _check_on_erc7765_received(from, to, token_id, data), 'Safe transfer failed'
            // );
        }

        fn _assert_owner(self: @ContractState, token_id: u256) {
            assert(self.ERC7765_owners.read(token_id) == get_caller_address(), 'Caller is not the token owner');
        }

        fn _assert_privilege_exists(self: @ContractState, token_id: u256) {
            assert(self.ERC7765_privileges_to_index.read(token_id) != 0, 'Invalid privilege id');
        }

        fn _assert_valid_account(self: @ContractState, account: ContractAddress) {
            assert(!account.is_zero(), 'Invalid account');
        }

        fn _assert_authorized(self: @ContractState, token_id: u256) {
            assert(
                self._is_approved_or_owner(get_caller_address(), token_id), 'Unauthorized'
            );
        }

        fn assert_token_exists(self: @ContractState, token_id: u256) {
            assert(self._exists(token_id), 'Invalid token id');
        }

    }

}