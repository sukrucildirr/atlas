// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import { IDAppControl } from "../interfaces/IDAppControl.sol";
import { IDAppIntegration } from "../interfaces/IDAppIntegration.sol";
import { IAtlas } from "../interfaces/IAtlas.sol";
import { IAtlasVerification } from "../interfaces/IAtlasVerification.sol";

import "../types/SolverCallTypes.sol";
import "../types/UserCallTypes.sol";
import "../types/DAppApprovalTypes.sol";

import { CallVerification } from "../libraries/CallVerification.sol";
import { CallBits } from "../libraries/CallBits.sol";

import "forge-std/Test.sol";

contract TxBuilder {
    using CallBits for uint32;
    using CallVerification for UserOperation;

    address public immutable control;
    address public immutable atlas;
    address public immutable verification;

    uint256 public immutable gas;

    constructor(address _control, address _atlas, address _verification) {
        control = _control;
        atlas = _atlas;
        verification = _verification;
        gas = 1_000_000;
    }

    function governanceNextNonce(address signatory) public view returns (uint256) {
        // Assume userNoncesSequential = false if control is not set
        if (control == address(0) || !IDAppControl(control).requireSequentialDAppNonces()) return 0;
        return IAtlasVerification(verification).getDAppNextNonce(signatory);
    }

    function userNextNonce(address user) public view returns (uint256) {
        // Assume userNoncesSequential = false if control is not set
        if (control == address(0)) return IAtlasVerification(verification).getUserNextNonce(user, false);
        return
            IAtlasVerification(verification).getUserNextNonce(user, IDAppControl(control).requireSequentialUserNonces());
    }

    function getControlCodeHash(address dAppControl) external view returns (bytes32) {
        return dAppControl.codehash;
    }

    function getBlockchainID() external view returns (uint256 chainId) {
        chainId = block.chainid;
    }

    function buildUserOperation(
        address from,
        address to,
        uint256 maxFeePerGas,
        uint256 value,
        uint256 deadline,
        bytes memory data
    )
        public
        view
        returns (UserOperation memory userOp)
    {
        userOp = UserOperation({
            from: from,
            to: atlas,
            value: value,
            gas: gas,
            maxFeePerGas: maxFeePerGas,
            nonce: userNextNonce(from),
            deadline: deadline,
            dapp: to,
            control: control,
            callConfig: IDAppControl(control).CALL_CONFIG(),
            sessionKey: address(0),
            data: data,
            signature: new bytes(0)
        });
    }

    function buildSolverOperation(
        UserOperation memory userOp,
        bytes memory solverOpData,
        address solverEOA,
        address solverContract,
        uint256 bidAmount,
        uint256 value
    )
        public
        view
        returns (SolverOperation memory solverOp)
    {
        // generate userOpHash depending on CallConfig.trustedOpHash allowed or not
        DAppConfig memory dConfig = IDAppControl(userOp.control).getDAppConfig(userOp);
        bytes32 userOpHash = IAtlasVerification(verification).getUserOperationHash(userOp);

        solverOp = SolverOperation({
            from: solverEOA,
            to: atlas,
            value: value,
            gas: gas,
            maxFeePerGas: userOp.maxFeePerGas,
            deadline: userOp.deadline,
            solver: solverContract,
            control: userOp.control,
            userOpHash: userOpHash,
            bidToken: IDAppControl(control).getBidFormat(userOp),
            bidAmount: bidAmount,
            data: solverOpData,
            signature: new bytes(0)
        });
    }

    function buildDAppOperation(
        address governanceEOA,
        UserOperation memory userOp,
        SolverOperation[] memory solverOps
    )
        public
        view
        returns (DAppOperation memory dAppOp)
    {
        DAppConfig memory dConfig = IDAppControl(userOp.control).getDAppConfig(userOp);

        // generate userOpHash depending on CallConfig.trustedOpHash allowed or not
        bytes32 userOpHash = IAtlasVerification(verification).getUserOperationHash(userOp);
        bytes32 callChainHash = CallVerification.getCallChainHash(dConfig, userOp, solverOps);

        dAppOp = DAppOperation({
            from: governanceEOA,
            to: atlas,
            nonce: governanceNextNonce(governanceEOA),
            deadline: userOp.deadline,
            control: userOp.control,
            bundler: address(0),
            userOpHash: userOpHash,
            callChainHash: callChainHash,
            signature: new bytes(0)
        });
    }
}
