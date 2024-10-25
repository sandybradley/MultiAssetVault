// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import "forge-std/Test.sol";
import "../src/MultiAssetVault.sol";
import "solmate/tokens/ERC20.sol";
import "solmate/utils/SafeTransferLib.sol";
import "solmate/test/utils/mocks/MockERC20.sol";

contract TestToken is MockERC20("Mock Token", "MTK", 18) {}

contract TestVault is MultiAssetVault {}

/**
 * @title MultiAssetVaultTest
 * @notice This contract tests the MultiAssetVault contract
 * @dev The test suite covers various functionalities, including deposits, minting shares, withdrawals, ETH handling, and edge case reverts.
 */
contract MultiAssetVaultTest is Test {
    MultiAssetVault vault;
    MockERC20 asset;

    address depositor = address(0x123);
    address receiver = address(0x456);
    address owner = address(0x789);

    /**
     * @notice Set up the testing environment
     * @dev Deploys a mock ERC20 asset and MultiAssetVault contract. Mints and approves tokens for testing, dealing initial funds to the depositor.
     */
    function setUp() public {
        // Deploy mock ERC20 asset and vault
        asset = new TestToken();
        vault = new TestVault();

        // Mint and approve tokens for testing
        vm.deal(depositor, 1000 ether);
        asset.mint(depositor, 1000 ether);
        vm.prank(depositor);
        asset.approve(address(vault), 1000 ether);
    }

    /**
     * @notice Tests the deposit functionality and minting of shares
     * @dev Verifies that the correct number of shares are minted upon deposit, and checks the balance of shares for the depositor.
     */
    function testDepositAndMintShares() public {
        vm.startPrank(depositor);

        uint256 depositAmount = 100 ether;
        uint256 expectedShares = vault.previewDeposit(asset, depositAmount);

        uint256 actualShares = vault.deposit(asset, depositAmount, depositor);

        assertEq(actualShares, expectedShares);
        assertEq(vault.balanceOf(depositor, uint256(uint160(address(asset)))), actualShares);
        assertEq(vault.totalShares(asset), actualShares);

        vm.stopPrank();
    }

    /**
     * @notice Tests the redeem functionality and withdrawal of assets
     * @dev Ensures that the correct amount of assets is withdrawn when redeeming shares, and verifies the depositor's balance and total shares.
     */
    function testRedeemAndWithdrawAssets() public {
        vm.startPrank(depositor);

        uint256 depositAmount = 100 ether;
        uint256 shares = vault.deposit(asset, depositAmount, depositor);

        uint256 expectedAmount = vault.previewRedeem(asset, shares);

        uint256 actualAmount = vault.redeem(asset, shares, receiver, depositor);

        assertEq(actualAmount, expectedAmount);
        assertEq(vault.totalShares(asset), 0);
        assertEq(vault.balanceOf(depositor, uint256(uint160(address(asset)))), 0);

        vm.stopPrank();
    }

    /**
     * @notice Tests the deposit functionality using native ETH
     * @dev Verifies that deposits made with native ETH are correctly handled, including the minting of shares and balance updates.
     */
    function testDepositNativeEth() public {
        vm.startPrank(depositor);

        uint256 depositAmount = 1 ether;
        uint256 expectedShares = vault.previewDeposit(ERC20(address(0)), depositAmount);

        vm.deal(depositor, depositAmount); // Provide ETH to depositor
        uint256 actualShares = vault.deposit{value: depositAmount}(ERC20(address(0)), depositAmount, depositor);

        assertEq(actualShares, expectedShares);
        assertEq(vault.balanceOf(depositor, uint256(uint160(address(0)))), actualShares);
        assertEq(vault.totalShares(ERC20(address(0))), actualShares);

        vm.stopPrank();
    }

    /**
     * @notice Tests the reversion when an incorrect amount of ETH is sent during a deposit
     * @dev Ensures that the contract correctly reverts if the ETH sent does not match the expected deposit amount.
     */
    function testRevertOnIncorrectEthAmount() public {
        vm.startPrank(depositor);

        uint256 depositAmount = 1 ether;

        vm.deal(depositor, depositAmount);

        vm.expectRevert(MultiAssetVault.IncorrectAmount.selector);
        vault.deposit{value: depositAmount - 0.1 ether}(ERC20(address(0)), depositAmount, depositor);

        vm.stopPrank();
    }

    /**
     * @notice Tests the reversion when attempting to mint zero shares
     * @dev Verifies that the contract reverts when a deposit amount of zero is used, preventing the minting of zero shares.
     */
    function testZeroSharesReversion() public {
        vm.startPrank(depositor);

        vm.expectRevert(MultiAssetVault.ZeroShares.selector);
        vault.deposit(asset, 0, depositor);

        vm.stopPrank();
    }
}
