//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.22;

interface IDAppIntegration {
    function initializeGovernance(address control) external;

    function addSignatory(address control, address signatory) external;

    function removeSignatory(address control, address signatory) external;

    function changeDAppGovernance(address oldGovernance, address newGovernance) external;

    function disableDApp(address dAppControl) external;

    function nextGovernanceNonce(address governanceSignatory) external view returns (uint256 nextNonce);

    function getGovFromControl(address dAppControl) external view returns (address governanceAddress);

    function isDAppSignatory(address dAppControl, address signatory) external view returns (bool);

    function dAppSignatories(address dAppControl) external view returns (address[] memory);
}
