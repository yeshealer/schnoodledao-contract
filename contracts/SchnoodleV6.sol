// contracts/SchnoodleV5.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "./imports/SchnoodleV5Base.sol";

/// @author Jason Payne (https://twitter.com/Neo42)
contract SchnoodleV5 is SchnoodleV5Base, AccessControlUpgradeable {
    uint256 private _version;
    address private _schnoodleStaking;
    address private _stakingFund;
    uint256 private _stakingPercent;
    mapping(address => TripMeter) private _tripMeters;

    bytes32 public constant FEE_EXEMPT = keccak256("FEE_EXEMPT");
    bytes32 public constant NO_TRANSFER = keccak256("NO_TRANSFER");
    bytes32 public constant STAKING_CONTRACT = keccak256("STAKING_CONTRACT");

    struct TripMeter {
        uint256 blockNumber;
        uint256 netBalance;
    }

    function upgrade(address schnoodleStaking) external onlyOwner {
        require(_version < 5, "Schnoodle: already upgraded");
        _version = 5;

        _setupRole(DEFAULT_ADMIN_ROLE, owner());
        grantRole(STAKING_CONTRACT, schnoodleStaking);
        _schnoodleStaking = schnoodleStaking;
        _stakingFund = address(uint160(uint256(keccak256(abi.encodePacked(block.timestamp, blockhash(block.number - 1))))));
    }

    // Transfer overrides

    function transfer(address recipient, uint256 amount) public virtual override returns (bool) {
        bool result = super.transfer(recipient, amount);
        _updateTripMeter(_msgSender(), recipient, amount);
        return result;
    }

    function transferFrom(address sender, address recipient, uint256 amount) public virtual override returns (bool) {
        bool result = super.transferFrom(sender, recipient, amount);
        _updateTripMeter(sender, recipient, amount);
        return result;
    }

    function _send(address from, address to, uint256 amount, bytes memory userData, bytes memory operatorData, bool requireReceptionAck) internal virtual override {
        super._send(from, to, amount, userData, operatorData, requireReceptionAck);
        _updateTripMeter(from, to, amount);
    }

    function _beforeTokenTransfer(address operator, address from, address to, uint256 amount) internal virtual override {
        require(!hasRole(NO_TRANSFER, from));

        if (from != address(0)) {
            uint256 standardAmount = _getStandardAmount(amount);
            uint256 balance = balanceOf(from);
            require(standardAmount > balance || standardAmount <= balance - lockedBalanceOf(from), "Schnoodle: transfer amount exceeds unstaked balance");
        }

        super._beforeTokenTransfer(operator, from, to, amount);
    }

    function payFeeAndDonate(address sender, address recipient, uint256 amount, uint256 reflectedAmount, function(address, address, uint256) internal transferCallback) internal virtual override {
        if (!hasRole(FEE_EXEMPT, sender)) {
            super.payFeeAndDonate(sender, recipient, amount, reflectedAmount, transferCallback);
            _transferTax(recipient, _stakingFund, amount, _stakingPercent, transferCallback);
        }
    }

    // Staking functions

    function stakingFund() external view returns (address) {
        return _stakingFund;
    }

    function changeStakingPercent(uint256 percent) external onlyOwner {
        _stakingPercent = percent;
        emit StakingPercentChanged(percent);
    }

    function stakingPercent() external view returns (uint256) {
        return _stakingPercent;
    }

    function stakingReward(address account, uint256 netReward, uint256 grossReward) external {
        require(hasRole(STAKING_CONTRACT, _msgSender()));
        _transferFromReflected(_stakingFund, account, _getReflectedAmount(netReward));

        // Burn the unused part of the gross reward
        _burn(_stakingFund, grossReward - netReward, "", "");
    }

    // Trip meter functions

    function tripMeter(address account) external view returns (TripMeter memory) {
        return _tripMeters[account];
    }

    function _updateTripMeter(address from, address to, uint256 amount) private {
        _updateTripMeter(from, -int256(amount));
        _updateTripMeter(to, int256(amount));
    }

    function _updateTripMeter(address account, int256 amount) private {
        if (account != address(0)) {
            if (_tripMeters[account].blockNumber == 0) {
                _resetTripMeter(account);
            } else {
                _tripMeters[account].netBalance = uint256(int256(_tripMeters[account].netBalance) + amount);
            }
        }
    }

    function resetTripMeter() public {
        _resetTripMeter(_msgSender());
    }

    function _resetTripMeter(address account) public {
        _tripMeters[account] = TripMeter(block.number, balanceOf(account));
    }

    // Calls to the SchnoodleStaking proxy contract

    function lockedBalanceOf(address account) private returns(uint256) {
        if (_schnoodleStaking == address(0)) return 0;
        (bool success, bytes memory result) = _schnoodleStaking.call(abi.encodeWithSignature("lockedBalanceOf(address)", account));
        assert(success);
        return abi.decode(result, (uint256));
    }

    event StakingPercentChanged(uint256 percent);
}
