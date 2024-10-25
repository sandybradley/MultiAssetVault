// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {ERC6909} from "solmate/tokens/ERC6909.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";

/**
 * @title MultiAssetVault
 * @notice A vault that supports multiple assets and provides functionality for ERC4626 and ERC6909.
 * @dev This contract allows deposits and withdrawals of various assets, including native ETH, using ERC4626 and ERC6909 standards.
 * Native ETH is represented by address(0).
 */
abstract contract MultiAssetVault is ERC6909 {
    using SafeTransferLib for ERC20;
    using FixedPointMathLib for uint256;

    /*//////////////////////////////////////////////////////////////
                               EVENTS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Emitted when assets are deposited into the vault.
     * @param caller The address of the caller initiating the deposit.
     * @param owner The address of the owner of the deposited assets.
     * @param asset The address of the asset being deposited.
     * @param assetAmount The amount of the asset being deposited.
     * @param shares The number of shares minted in exchange for the deposit.
     */
    event Deposit(
        address indexed caller, address indexed owner, ERC20 indexed asset, uint256 assetAmount, uint256 shares
    );

    /**
     * @notice Emitted when assets are withdrawn from the vault.
     * @param caller The address of the caller initiating the withdrawal.
     * @param receiver The address of the receiver of the withdrawn assets.
     * @param owner The address of the owner of the withdrawn shares.
     * @param asset The address of the asset being withdrawn.
     * @param assetAmount The amount of the asset being withdrawn.
     * @param shares The number of shares burned in exchange for the withdrawal.
     */
    event Withdraw(
        address indexed caller,
        address indexed receiver,
        address indexed owner,
        ERC20 asset,
        uint256 assetAmount,
        uint256 shares
    );

    /*//////////////////////////////////////////////////////////////
                             VAULT STORAGE
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Tracks the total number of shares issued for each asset.
     * @dev Maps each ERC20 asset address to the total shares issued for that asset.
     */
    mapping(ERC20 asset => uint256 totalShares) public totalShares;

    /*//////////////////////////////////////////////////////////////
                               ERRORS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Reverts when the amount of shares calculated for deposit = 0.
     */
    error ZeroShares();

    /**
     * @notice Reverts when the amount of ETH sent with the transaction does not match the expected amount.
     */
    error IncorrectAmount();

    /*//////////////////////////////////////////////////////////////
                           DEPOSIT/WITHDRAWAL LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Deposits a specified amount of an asset into the vault, minting corresponding shares.
     * @dev If depositing ETH, the value sent with the transaction must match the specified amount.
     * Emits a {Deposit} event.
     * @param asset The ERC20 token being deposited (use address(0) for ETH).
     * @param amount The amount of the asset to deposit.
     * @param receiver The address to receive the minted shares.
     * @return shares The number of shares minted in exchange for the deposit.
     */
    function deposit(ERC20 asset, uint256 amount, address receiver) public payable returns (uint256 shares) {
        // check if eth
        if (address(asset) == address(0)) {
            if (msg.value != amount) revert IncorrectAmount();
        }

        shares = previewDeposit(asset, amount);
        if (shares == 0) revert ZeroShares();

        if (address(asset) != address(0)) {
            asset.safeTransferFrom(msg.sender, address(this), amount);
        }

        totalShares[asset] += shares;
        _mint(receiver, uint256(uint160(address(asset))), shares);

        emit Deposit(msg.sender, receiver, asset, amount, shares);
    }

    /**
     * @notice Redeems a specified number of shares for the underlying asset.
     * @dev Burns the specified number of shares and transfers the corresponding amount of the asset to the receiver.
     * Emits a {Withdraw} event.
     * @param asset The ERC20 token to be redeemed (use address(0) for ETH).
     * @param shares The number of shares to redeem.
     * @param receiver The address to receive the redeemed assets.
     * @param owner The address that owns the shares being redeemed.
     * @return amount The amount of the underlying asset returned for the redeemed shares.
     */
    function redeem(ERC20 asset, uint256 shares, address receiver, address owner) public returns (uint256 amount) {
        amount = previewRedeem(asset, shares);
        _approveOrTransferFrom(owner, address(asset), shares);

        totalShares[asset] -= shares;
        _burn(owner, uint256(uint160(address(asset))), shares);

        emit Withdraw(msg.sender, receiver, owner, asset, amount, shares);
        if (address(asset) == address(0)) {
            SafeTransferLib.safeTransferETH(receiver, amount);
        } else {
            asset.safeTransfer(receiver, amount);
        }
    }

    /*//////////////////////////////////////////////////////////////
                           ACCOUNTING LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Returns the total amount of the specified asset held in the vault.
     * @dev For ETH, this returns the contract's balance; for ERC20 tokens, it returns the token balance.
     * @param asset The ERC20 token to query (use address(0) for ETH).
     * @return The total amount of the specified asset held in the vault.
     */
    function totalAssets(ERC20 asset) public view returns (uint256) {
        if (address(asset) == address(0)) return address(this).balance;
        else return asset.balanceOf(address(this));
    }

    /**
     * @notice Converts an asset amount to the equivalent number of shares.
     * @dev This conversion is based on the current total assets and total shares for the specified asset.
     * @param asset The ERC20 token to convert (use address(0) for ETH).
     * @param assetAmount The amount of the asset to convert to shares.
     * @return The number of shares equivalent to the specified asset amount.
     */
    function convertToShares(ERC20 asset, uint256 assetAmount) public view returns (uint256) {
        uint256 supply = totalShares[asset];
        return supply == 0 ? assetAmount : assetAmount.mulDivDown(supply, totalAssets(asset));
    }

    /**
     * @notice Converts a specified number of shares to the equivalent asset amount.
     * @dev This conversion is based on the current total assets and total shares for the specified asset.
     * @param asset The ERC20 token to convert (use address(0) for ETH).
     * @param shares The number of shares to convert to assets.
     * @return The amount of the asset equivalent to the specified number of shares.
     */
    function convertToAssets(ERC20 asset, uint256 shares) public view returns (uint256) {
        uint256 supply = totalShares[asset];
        return supply == 0 ? shares : shares.mulDivDown(totalAssets(asset), supply);
    }

    /**
     * @notice Previews the number of shares that would be minted for a given asset deposit.
     * @dev This is a view function that does not modify state.
     * @param asset The ERC20 token to be deposited (use address(0) for ETH).
     * @param assetAmount The amount of the asset to deposit.
     * @return The number of shares that would be minted for the specified asset amount.
     */
    function previewDeposit(ERC20 asset, uint256 assetAmount) public view returns (uint256) {
        return convertToShares(asset, assetAmount);
    }

    /**
     * @notice Previews the amount of assets that would be returned for a given number of shares.
     * @dev This is a view function that does not modify state.
     * @param asset The ERC20 token to be redeemed (use address(0) for ETH).
     * @param shares The number of shares to redeem.
     * @return The amount of the underlying asset that would be returned for the specified number of shares.
     */
    function previewRedeem(ERC20 asset, uint256 shares) public view returns (uint256) {
        return convertToAssets(asset, shares);
    }

    /*//////////////////////////////////////////////////////////////
                     INTERNAL TRANSFER/APPROVE LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Private function to approve or transfer shares on behalf of the owner.
     * @dev If the caller is not the owner, it checks if the caller is an approved operator for the owner.
     * @param owner The address of the shares owner.
     * @param asset Asset address
     * @param shares The number of shares to approve or transfer.
     */
    function _approveOrTransferFrom(address owner, address asset, uint256 shares) internal {
        if (msg.sender != owner) {
            uint256 allowed = allowance[owner][msg.sender][uint256(uint160(asset))];
            if (allowed != type(uint256).max) {
                allowance[owner][msg.sender][uint256(uint160(asset))] = allowed - shares;
            }
        }
    }

    /*//////////////////////////////////////////////////////////////
                           RECEIVE FUNCTION
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Fallback function to handle ETH deposits.
     * @dev This function allows the contract to accept ETH deposits
     */
    receive() external payable { }
}
