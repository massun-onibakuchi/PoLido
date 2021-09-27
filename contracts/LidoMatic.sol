// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";

import "./interfaces/IValidatorShare.sol";

contract LidoMatic is AccessControl, ERC20 {
    ////////////////////////////////////////////////////////////
    ///                                                      ///
    ///               ***State Variables***                  ///
    ///                                                      ///
    ////////////////////////////////////////////////////////////

    mapping(address => RequestWithdraw) public userToWithdrawRequest;
    mapping(address => uint256) public userToShares;
    mapping(address => uint256) public validator2Nonce;
    IValidatorShare[] validatorShares;
    uint256 public totalDelegated;
    uint256 public totalBuffered;
    address public token;
    bool paused;

    struct RequestWithdraw {
        uint256 amount;
        uint256 validatorNonce;
        uint256 requestTime;
        address validatorAddress;
        bool active;
    }

    /** Roles */
    bytes32 public constant GOVERNANCE = keccak256("GOVERNANCE");
    bytes32 public constant PAUSE_ROLE = keccak256("PAUSE_ROLE");
    bytes32 public constant MANAGE_FEE = keccak256("MANAGE_FEE");
    bytes32 public constant BURN_ROLE = keccak256("BURN_ROLE");
    bytes32 public constant SET_TREASURY = keccak256("SET_TREASURY");

    /** Modifiers */
    modifier auth(bytes32 _role) {
        require(hasRole(_role, msg.sender));
        _;
    }

    modifier notPaused() {
        require(!paused, "System is paused");
        _;
    }

    /**
     * @param _token - Address of MATIC token on Ethereum Mainnet
     */
    constructor(address _token) ERC20("Staked MATIC", "StMATIC") {
        token = _token;
    }

    /**
     * @dev Send funds to LidoMatic contract and mints StMATIC to msg.sender
     * @notice Requires that msg.sender has approved _amount of MATIC to this contract
     * @param _amount - Amount of MATIC sent from msg.sender to this contract
     * @return Amount of StMATIC shares generated
     */
    function submit(uint256 _amount) external returns (uint256) {
        require(_amount > 0, "Invalid amount");

        IERC20(token).transferFrom(msg.sender, address(this), _amount);

        uint256 totalShares = totalSupply();
        uint256 totalPooledMatic = totalBuffered + totalDelegated;
        uint256 amountToMint = totalShares != 0
            ? (_amount * totalShares) / totalPooledMatic
            : _amount;

        _mint(msg.sender, amountToMint);

        totalBuffered += _amount;

        return amountToMint;
    }

    /**
     * How to select a validator that we are going to withdraw from?
     *
     * @dev Stores users request to withdraw into a RequestWithdraw struct
     * @param _amount - Amount of MATIC that is requested to withdraw
     */
    function requestWithdraw(uint256 _amount) external notPaused {
        // Add a function that converts MATIC to StMATIC and reverse
        // Check how many StMATIC does a caller have
        // Add a mapping between a validator address and a nonce (starts at 1)
        // Increment nonce by 1 everytime a user calls a withdrawal function
        // Burn StMATIC after checking if _amount satisfies user's balance
        // A nonce is dependent on a validator
        // Add a nonce per user
        uint256 callerBalanceInMATIC = balanceOf(msg.sender);

        if (callerBalanceInMATIC <= _amount) {
            _burn(msg.sender, _amount);
        }

        // TODO this is just a mock
        uint256 validatorId = operator.getValidatorId();
        uint256 validatorNonce = operator.getValidatorNonce();
        uint256 validatorShare = operator.getValidatorShareAddress();

        userToWithdrawRequest[msg.sender] = RequestWithdraw(
            _amount,
            validatorNonce,
            validatorId
        );

        sellVoucher_new(
            validatorShare,
            callerBalanceInMATIC,
            callerBalanceInMATIC
        );
    }

    /**
     * @dev Delegates tokens to validator share contract
     */
    function delegate(IValidatorShare validatorShare)
        external
        auth(GOVERNANCE)
    {
        uint256 tokenBalance = IERC20(token).balanceOf(address(this));
        IERC20(token).transfer(address(validatorShare), tokenBalance);
    }

    /**
     * @dev Claims tokens from validator share and sends them to the
     * user if his request is in the userToWithdrawRequest
     */
    function claimTokens() external {
        RequestWithdraw userRequest = userToWithdrawRequest[msg.sender];

        require(userRequest.amount, "Not allowed to claim");

        IValidatorShare validatorShare = operator.getValidatorShare(
            userRequest.validatorId
        );

        unstakeClaimTokens_new(
            address(validatorShare),
            userRequest.validatorNonce
        );

        IERC20(token).transfer(msg.sender, userRequest.amount);
    }

    /**
     * @notice Only PAUSE_ROLE can call this function. This function puts certain functionalities on pause.
     * @param _pause - Determines if the contract will be paused (true) or unpaused (false)
     */
    function pause(bool _pause) external auth(PAUSE_ROLE) {
        paused = _pause;
    }

    ////////////////////////////////////////////////////////////
    /////                                                    ///
    /////             ***ValidatorShare API***               ///
    /////                                                    ///
    ////////////////////////////////////////////////////////////

    /**
     * @dev API for delegatet buying vouchers from validatorShare
     * @param _validatorShare - Address of validatorShare contract
     * @param _amount - Amount of MATIC to use for buying vouchers
     * @param _minSharesToMint - Minimum of shares that is bought with _amount of MATIC
     * @return Actual amount of MATIC used to buy voucher, might differ from _amount because of _minSharesToMint
     */
    function buyVoucher(
        address _validatorShare,
        uint256 _amount,
        uint256 _minSharesToMint
    ) public returns (uint256) {
        uint256 amountSpent = IValidatorShare(_validatorShare).buyVoucher(
            _amount,
            _minSharesToMint
        );

        return amountSpent;
    }

    /**
     * @dev API for delegated restaking rewards to validatorShare
     * @param _validatorShare - Address of validatorShare contract
     */
    function restake(address _validatorShare) public {
        IValidatorShare(_validatorShare).restake();
    }

    /**
     * @dev API for delegated unstaking and claiming tokens from validatorShare
     * @param _validatorShare - Address of validatorShare contract
     * @param _unbondNonce - TODO
     */
    function unstakeClaimTokens_new(
        address _validatorShare,
        uint256 _unbondNonce
    ) public {
        IValidatorShare(_validatorShare).unstakeClaimTokens_new(_unbondNonce);
    }

    /**
     * @dev API for delegated selling vouchers from validatorShare
     * @param _validatorShare - Address of validatorShare contract
     * @param _claimAmount - Amount of MATIC to claim
     * @param _maximumSharesToBurn - Maximum amount of shares to burn
     */
    function sellVoucher_new(
        address _validatorShare,
        uint256 _claimAmount,
        uint256 _maximumSharesToBurn
    ) public {
        IValidatorShare(_validatorShare).sellVoucher_new(
            _claimAmount,
            _maximumSharesToBurn
        );
    }

    /**
     * @dev API for getting total stake of this contract from validatorShare
     * @param _validatorShare - Address of validatorShare contract
     * @return Total stake of this contract and MATIC -> share exchange rate
     */
    function getTotalStake(IValidatorShare _validatorShare)
        public
        view
        returns (uint256, uint256)
    {
        return _validatorShare.getTotalStake(address(this));
    }

    /**
     * @dev API for liquid rewards of this contract from validatorShare
     * @param _validatorShare - Address of validatorShare contract
     * @return Liquid rewards of this contract
     */
    function getLiquidRewards(IValidatorShare _validatorShare)
        public
        view
        returns (uint256)
    {
        return _validatorShare.getLiquidRewards(address(this));
    }

    ////////////////////////////////////////////////////////////
    /////                                                    ///
    /////            ***Helpers & Utilities***               ///
    /////                                                    ///
    ////////////////////////////////////////////////////////////

    /**
     * @dev Helper function for that returns total pooled MATIC
     * @return Total pooled MATIC
     */
    function getTotalStakeAcrossAllValidators() public view returns (uint256) {
        uint256 totalStake;

        for (uint256 i = 0; i < validatorShares.length; i++) {
            (uint256 currValidatorShare, ) = getTotalStake(validatorShares[i]);

            totalStake += currValidatorShare;
        }

        return totalStake;
    }

    /**
     * @dev Function that converts users StMATIC to MATIC
     * @return Users balance in MATIC
     */
    function getUserBalanceInMATIC() public view returns (uint256) {
        uint256 userShares = balanceOf(msg.sender);
        uint256 totalShares = totalSupply();
        uint256 totalPooledMATIC = getTotalStakeAcrossAllValidators();

        uint256 userBalanceInMATIC = (userShares * totalPooledMATIC) /
            totalShares;

        return userBalanceInMATIC;
    }
}
