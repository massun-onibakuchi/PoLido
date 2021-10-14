//SPDX-License-Identifier: Unlicense
pragma solidity 0.8.7;

import "../lib/Operator.sol";

/// @title ValidatorFactoryStorage
/// @author 2021 Shardlabs
/// @notice Validator factory storage
contract ValidatorFactoryStorage {
    // ====================================================================
    // =========================== Global Vars ============================
    // ====================================================================

    address[] internal validators;

    Operator.ValidatorFactoryState internal state;

    // ====================================================================
    // ============================== EVENTS ==============================
    // ====================================================================

    event CreateValidator(address validator);
    event SetOperatorContract(address operator);
    event SetValidatorImplementation(address validatorImplementation);
}