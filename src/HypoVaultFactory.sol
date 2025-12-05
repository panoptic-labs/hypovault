// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {HypoVault} from "./HypoVault.sol";
import {IVaultAccountant} from "./interfaces/IVaultAccountant.sol";
import "lib/boring-vault/lib/openzeppelin-contracts/contracts/proxy/Clones.sol";

/// @title HypoVault Factory
/// @author Axicon Labs Limited
/// @notice Factory contract for creating HypoVault instances
contract HypoVaultFactory {
    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Emitted when a vault is created.
    /// @param underlyingToken The address of the underlying token
    /// @param manager The address of the vault manager
    /// @param accountant The address of the vault accountant
    /// @param vault The address of the newly created vault
    /// @param performanceFeeBps The performance fee in basis points
    /// @param symbol The symbol of the share token
    /// @param name The name of the share token
    event VaultCreated(
        address indexed underlyingToken,
        address indexed manager,
        IVaultAccountant indexed accountant,
        address vault,
        uint256 performanceFeeBps,
        string symbol,
        string name
    );

    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/
    /// @notice Reference implementation of the `HypoVault` to clone.
    address public immutable hypoVaultReference;

    /*//////////////////////////////////////////////////////////////
                               FACTORY LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice Initializes the factory with a HypoVault implementation
    /// @param _hypoVaultReference The address of the HypoVault implementation contract
    constructor(address _hypoVaultReference) {
        hypoVaultReference = _hypoVaultReference;
    }

    /// @notice Creates a new HypoVault instance.
    /// @param underlyingToken The token used to denominate deposits and withdrawals
    /// @param manager The account authorized to execute deposits, withdrawals, and make arbitrary function calls from the vault
    /// @param accountant The contract that reports the net asset value of the vault
    /// @param performanceFeeBps The performance fee, in basis points, taken on each profitable withdrawal
    /// @param symbol The symbol of the share token
    /// @param name The name of the share token
    /// @return vault The address of the newly created vault
    function createVault(
        address underlyingToken,
        address manager,
        IVaultAccountant accountant,
        uint256 performanceFeeBps,
        string memory symbol,
        string memory name,
        bytes32 salt
    ) external returns (address payable vault) {
        vault = payable(Clones.cloneDeterministic(hypoVaultReference, salt));

        HypoVault(vault).initialize(
            underlyingToken,
            manager,
            accountant,
            performanceFeeBps,
            symbol,
            name
        );

        emit VaultCreated(
            underlyingToken,
            manager,
            accountant,
            vault,
            performanceFeeBps,
            symbol,
            name
        );
    }
}
