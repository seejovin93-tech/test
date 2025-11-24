// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract ChronosGuardAnchor {
    address public immutable CHRONOS_GUARD;
    bytes32 public stateRoot;
    uint256 public lastUpdateTime;
    uint256 constant RECOVERY_PERIOD = 365 days;
    address public immutable RECOVERY_ADDRESS;

    event StateUpdated(bytes32 indexed newRoot, uint256 timestamp);
    event RecoveryTriggered(address beneficiary);

    constructor(address _guard, address _recovery) {
        CHRONOS_GUARD = _guard;
        RECOVERY_ADDRESS = _recovery;
        lastUpdateTime = block.timestamp;
    }

    function updateStateRoot(bytes32 newRoot) external {
        require(msg.sender == CHRONOS_GUARD, "Access Denied");
        stateRoot = newRoot;
        lastUpdateTime = block.timestamp;
        emit StateUpdated(newRoot, block.timestamp);
    }

    function triggerRecovery() external {
        require(block.timestamp >= lastUpdateTime + RECOVERY_PERIOD, "Active");
        emit RecoveryTriggered(RECOVERY_ADDRESS);
    }
}
