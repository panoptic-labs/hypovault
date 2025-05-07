// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../src/HypoVault.sol";
import {ERC20S} from "lib/panoptic-v1.1/test/foundry/testUtils/ERC20S.sol";

contract VaultAccountantMock {
    uint256 public nav;

    address public expectedVault;

    bytes public expectedManagerInput;

    function setNav(uint256 _nav) external {
        nav = _nav;
    }

    function setExpectedVault(address _expectedVault) external {
        expectedVault = _expectedVault;
    }

    function setExpectedManagerInput(bytes memory _expectedManagerInput) external {
        expectedManagerInput = _expectedManagerInput;
    }

    function computeNAV(address vault, bytes memory managerInput) external view returns (uint256) {
        require(vault == expectedVault, "Invalid vault");
        if (managerInput.length > 0) {
            require(
                keccak256(managerInput) == keccak256(expectedManagerInput),
                "Invalid manager input"
            );
        }
        return nav;
    }
}

contract HypoVaultTest is Test {
    VaultAccountantMock public accountant;

    HypoVault public vault;

    ERC20S public token;

    address Manager = address(0x1234);
    address Alice = address(0x123456);
    address Bob = address(0x12345678);
    address Swapper = address(0x123456789);
    address Charlie = address(0x1234567891);
    address Admin = address(0x12345678912);

    function setUp() public {
        accountant = new VaultAccountantMock();
        token = new ERC20S("Test Token", "TEST", 18);
        vault = new HypoVault(address(token), Manager, IVaultAccountant(address(accountant)), 100);
        accountant.setExpectedVault(address(vault));

        token.mint(Alice, 1000000 ether);
        token.mint(Bob, 1000000 ether);
        token.mint(Swapper, 1000000 ether);
        token.mint(Charlie, 1000000 ether);
        token.mint(Admin, 1000000 ether);
        token.mint(Manager, 1000000 ether);
        vm.startPrank(Bob);
        token.approve(address(vault), 1000000 ether);
        vm.startPrank(Swapper);
        token.approve(address(vault), 1000000 ether);
        vm.startPrank(Charlie);
        token.approve(address(vault), 1000000 ether);
        vm.startPrank(Admin);
        token.approve(address(vault), 1000000 ether);
        vm.startPrank(Manager);
        token.approve(address(vault), 1000000 ether);
        vm.startPrank(Alice);
        token.approve(address(vault), 1000000 ether);
    }

    function test_vaultParameters() public view {
        assertEq(vault.underlyingToken(), address(token));
        assertEq(vault.manager(), Manager);
        assertEq(address(vault.accountant()), address(accountant));
        assertEq(vault.performanceFeeBps(), 100);
    }

    function test_deposit_full_single_epoch0() public {
        uint256 aliceBalance = token.balanceOf(Alice);
        vault.requestDeposit(100 ether, Alice);
        assertEq(token.balanceOf(address(vault)), 100 ether);
        assertEq(aliceBalance - 100 ether, token.balanceOf(Alice));

        vm.startPrank(Manager);
        accountant.setNav(100 ether);
        vault.fulfillDeposits(100 ether, "");

        vault.executeDeposit(Alice, 0);

        assertEq(vault.balanceOf(Alice), 100_000_000 ether);
        assertEq(vault.totalSupply(), 1_000_000 + 100_000_000 ether);
    }
}
