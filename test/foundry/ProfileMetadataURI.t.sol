// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import './base/BaseTest.t.sol';
import './MetaTxNegatives.t.sol';
import {Events} from 'contracts/libraries/Events.sol';

contract ProfileMetadataURITest is BaseTest {
    function _setProfileMetadataURI(
        uint256 pk,
        uint256 profileId,
        string memory metadataURI
    ) internal virtual {
        vm.prank(vm.addr(pk));
        hub.setProfileMetadataURI(profileId, metadataURI);
    }

    // Negatives
    function testCannotSetProfileMetadataURINotExecutor() public {
        vm.expectRevert(Errors.ExecutorInvalid.selector);
        _setProfileMetadataURI({
            pk: alienSignerKey,
            profileId: newProfileId,
            metadataURI: MOCK_URI
        });
    }

    // Positives
    function testExecutorSetProfileMetadataURI() public {
        assertEq(hub.getProfileMetadataURI(newProfileId), '');
        vm.prank(profileOwner);
        hub.setDelegatedExecutorApproval(otherSigner, true);

        _setProfileMetadataURI({
            pk: otherSignerKey,
            profileId: newProfileId,
            metadataURI: MOCK_URI
        });
        assertEq(hub.getProfileMetadataURI(newProfileId), MOCK_URI);
    }

    function testSetProfileMetadataURI() public {
        assertEq(hub.getProfileMetadataURI(newProfileId), '');

        _setProfileMetadataURI({
            pk: profileOwnerKey,
            profileId: newProfileId,
            metadataURI: MOCK_URI
        });
        assertEq(hub.getProfileMetadataURI(newProfileId), MOCK_URI);
    }

    // Events
    function expectProfileMetadataSetEvent() public {
        vm.expectEmit(true, true, true, true, address(hub));
        emit Events.ProfileMetadataSet({
            profileId: newProfileId,
            metadata: MOCK_URI,
            timestamp: block.timestamp
        });
    }

    function testSetProfileMetadataURI_EmitsProperEvent() public {
        expectProfileMetadataSetEvent();
        testSetProfileMetadataURI();
    }

    function testExecutorSetProfileMetadataURI_EmitsProperEvent() public {
        expectProfileMetadataSetEvent();
        testExecutorSetProfileMetadataURI();
    }
}

contract ProfileMetadataURITest_MetaTx is ProfileMetadataURITest, MetaTxNegatives {
    mapping(address => uint256) cachedNonceByAddress;

    function setUp() public override(MetaTxNegatives, TestSetup) {
        TestSetup.setUp();
        MetaTxNegatives.setUp();

        cachedNonceByAddress[alienSigner] = _getSigNonce(alienSigner);
        cachedNonceByAddress[otherSigner] = _getSigNonce(otherSigner);
        cachedNonceByAddress[profileOwner] = _getSigNonce(profileOwner);
    }

    function _setProfileMetadataURI(
        uint256 pk,
        uint256 profileId,
        string memory metadataURI
    ) internal virtual override {
        address signer = vm.addr(pk);
        uint256 nonce = cachedNonceByAddress[signer];
        uint256 deadline = type(uint256).max;

        bytes32 digest = _getSetProfileMetadataURITypedDataHash(
            newProfileId,
            MOCK_URI,
            nonce,
            deadline
        );

        hub.setProfileMetadataURIWithSig(
            DataTypes.SetProfileMetadataURIWithSigData({
                delegatedSigner: signer == profileOwner ? address(0) : signer,
                profileId: newProfileId,
                metadataURI: MOCK_URI,
                sig: _getSigStruct(pk, digest, deadline)
            })
        );
    }

    function _executeMetaTx(
        uint256 signerPk,
        uint256 nonce,
        uint256 deadline
    ) internal virtual override {
        bytes32 digest = _getSetProfileMetadataURITypedDataHash(
            newProfileId,
            MOCK_URI,
            nonce,
            deadline
        );

        hub.setProfileMetadataURIWithSig(
            DataTypes.SetProfileMetadataURIWithSigData({
                delegatedSigner: address(0),
                profileId: newProfileId,
                metadataURI: MOCK_URI,
                sig: _getSigStruct(signerPk, digest, deadline)
            })
        );
    }

    function _getDefaultMetaTxSignerPk() internal virtual override returns (uint256) {
        return profileOwnerKey;
    }
}
