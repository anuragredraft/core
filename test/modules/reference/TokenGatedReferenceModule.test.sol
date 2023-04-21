// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import 'test/base/BaseTest.t.sol';
import {TokenGatedReferenceModule, GateParams} from 'contracts/modules/reference/TokenGatedReferenceModule.sol';
import {Types} from 'contracts/libraries/constants/Types.sol';
import {ArrayHelpers} from 'test/helpers/ArrayHelpers.sol';
import {Currency} from 'test/mocks/Currency.sol';
import {NFT} from 'test/mocks/NFT.sol';

contract TokenGatedReferenceModuleBase is BaseTest {
    using stdJson for string;
    TokenGatedReferenceModule tokenGatedReferenceModule;

    NFT nft;
    Currency currency;
    uint256 profileId;

    event TokenGatedReferencePublicationCreated(
        uint256 indexed profileId,
        uint256 indexed pubId,
        address tokenAddress,
        uint256 minThreshold
    );

    function setUp() public override {
        super.setUp();
        currency = new Currency();
        nft = new NFT();
        profileId = _createProfile(profileOwner);
    }

    // Deploy & Whitelist TokenGatedReferenceModule
    constructor() TestSetup() {
        if (fork && keyExists(string(abi.encodePacked('.', forkEnv, '.TokenGatedReferenceModule')))) {
            tokenGatedReferenceModule = TokenGatedReferenceModule(
                json.readAddress(string(abi.encodePacked('.', forkEnv, '.TokenGatedReferenceModule')))
            );
            console.log('Testing against already deployed module at:', address(tokenGatedReferenceModule));
        } else {
            vm.prank(deployer);
            tokenGatedReferenceModule = new TokenGatedReferenceModule(hubProxyAddr);
        }
    }
}

/////////
// Publication Creation with TokenGatedReferenceModule
//
contract TokenGatedReferenceModule_Publication is TokenGatedReferenceModuleBase {
    constructor() TokenGatedReferenceModuleBase() {}

    // Negatives
    function testCannotPostWithZeroTokenAddress() public {
        vm.expectRevert(Errors.InitParamsInvalid.selector);
        vm.prank(address(hub));
        tokenGatedReferenceModule.initializeReferenceModule(
            1,
            2,
            address(3),
            abi.encode(GateParams({tokenAddress: address(0), minThreshold: 1}))
        );
    }

    function testCannotPostWithZeroMinThreshold() public {
        vm.expectRevert(Errors.InitParamsInvalid.selector);
        vm.prank(address(hub));
        tokenGatedReferenceModule.initializeReferenceModule(
            1,
            2,
            address(3),
            abi.encode(GateParams({tokenAddress: address(currency), minThreshold: 0}))
        );
    }

    function testCannotCallInitializeFromNonHub(address from) public {
        vm.assume(from != address(hub));
        vm.prank(from);
        vm.expectRevert(Errors.NotHub.selector);
        tokenGatedReferenceModule.initializeReferenceModule(
            profileId,
            1,
            profileOwner,
            abi.encode(GateParams({tokenAddress: address(currency), minThreshold: 1}))
        );
    }

    function testCannotProcessCommentFromNonHub(address from) public {
        vm.assume(from != address(hub));
        vm.prank(from);
        vm.expectRevert(Errors.NotHub.selector);
        tokenGatedReferenceModule.processComment(
            Types.ProcessCommentParams({
                profileId: profileId,
                transactionExecutor: profileOwner,
                pointedProfileId: profileId,
                pointedPubId: 1,
                referrerProfileIds: _emptyUint256Array(),
                referrerPubIds: _emptyUint256Array(),
                referrerPubTypes: _emptyPubTypesArray(),
                data: ''
            })
        );
    }

    function testCannotProcessQuoteFromNonHub(address from) public {
        vm.assume(from != address(hub));
        vm.prank(from);
        vm.expectRevert(Errors.NotHub.selector);
        tokenGatedReferenceModule.processQuote(
            Types.ProcessQuoteParams({
                profileId: profileId,
                transactionExecutor: profileOwner,
                pointedProfileId: profileId,
                pointedPubId: 1,
                referrerProfileIds: _emptyUint256Array(),
                referrerPubIds: _emptyUint256Array(),
                referrerPubTypes: _emptyPubTypesArray(),
                data: ''
            })
        );
    }

    function testCannotProcessMirrorFromNonHub(address from) public {
        vm.assume(from != address(hub));
        vm.prank(from);
        vm.expectRevert(Errors.NotHub.selector);
        tokenGatedReferenceModule.processMirror(
            Types.ProcessMirrorParams({
                profileId: profileId,
                transactionExecutor: profileOwner,
                pointedProfileId: profileId,
                pointedPubId: 1,
                referrerProfileIds: _emptyUint256Array(),
                referrerPubIds: _emptyUint256Array(),
                referrerPubTypes: _emptyPubTypesArray(),
                data: ''
            })
        );
    }

    // Scenarios
    function testCanInitializeTokenGatedReferenceModule(uint256 profileId, uint256 pubId, uint256 minThreshold) public {
        vm.assume(profileId != 0);
        vm.assume(pubId != 0);
        vm.assume(minThreshold != 0);

        vm.prank(address(hub));
        tokenGatedReferenceModule.initializeReferenceModule(
            profileId,
            pubId,
            address(0),
            abi.encode(GateParams({tokenAddress: address(currency), minThreshold: minThreshold}))
        );
    }

    function testCreatePublicationWithTokenGatedReferenceModule_EmitsExpectedEvents(
        uint256 profileId,
        uint256 pubId,
        uint256 minThreshold
    ) public {
        vm.assume(profileId != 0);
        vm.assume(pubId != 0);
        vm.assume(minThreshold != 0);

        vm.expectEmit(true, true, true, true, address(tokenGatedReferenceModule));
        emit TokenGatedReferencePublicationCreated(profileId, pubId, address(currency), minThreshold);
        vm.prank(address(hub));
        tokenGatedReferenceModule.initializeReferenceModule(
            profileId,
            pubId,
            address(0),
            abi.encode(GateParams({tokenAddress: address(currency), minThreshold: minThreshold}))
        );
    }
}

/////////
// ERC20-Gated Reference
//
contract TokenGatedReferenceModule_ERC20_Gated is TokenGatedReferenceModuleBase {
    function _initialize(uint256 publisherProfileId, uint256 publisherPubId, uint256 minThreshold) internal {
        vm.assume(publisherProfileId != 0);
        vm.assume(publisherPubId != 0);
        vm.assume(minThreshold != 0);
        vm.prank(address(hub));
        tokenGatedReferenceModule.initializeReferenceModule(
            publisherProfileId,
            publisherPubId,
            address(0),
            abi.encode(GateParams({tokenAddress: address(currency), minThreshold: minThreshold}))
        );
    }

    constructor() TokenGatedReferenceModuleBase() {}

    // Negatives
    function testCannotProcessComment_IfNotEnoughBalance(
        uint256 publisherProfileId,
        uint256 publisherPubId,
        uint256 minThreshold
    ) public {
        assertEq(currency.balanceOf(address(profileOwner)), 0);

        _initialize(publisherProfileId, publisherPubId, minThreshold);

        vm.expectRevert(TokenGatedReferenceModule.NotEnoughBalance.selector);

        vm.prank(address(hub));
        tokenGatedReferenceModule.processComment(
            Types.ProcessCommentParams({
                profileId: profileId,
                transactionExecutor: profileOwner,
                pointedProfileId: publisherProfileId,
                pointedPubId: publisherPubId,
                referrerProfileIds: _emptyUint256Array(),
                referrerPubIds: _emptyUint256Array(),
                referrerPubTypes: _emptyPubTypesArray(),
                data: ''
            })
        );
    }

    function testCannotProcessMirror_IfNotEnoughBalance(
        uint256 publisherProfileId,
        uint256 publisherPubId,
        uint256 minThreshold
    ) public {
        assertEq(currency.balanceOf(address(profileOwner)), 0);

        _initialize(publisherProfileId, publisherPubId, minThreshold);

        vm.expectRevert(TokenGatedReferenceModule.NotEnoughBalance.selector);
        vm.prank(address(hub));
        tokenGatedReferenceModule.processMirror(
            Types.ProcessMirrorParams({
                profileId: profileId,
                transactionExecutor: profileOwner,
                pointedProfileId: publisherProfileId,
                pointedPubId: publisherPubId,
                referrerProfileIds: _emptyUint256Array(),
                referrerPubIds: _emptyUint256Array(),
                referrerPubTypes: _emptyPubTypesArray(),
                data: ''
            })
        );
    }

    function testCannotProcessQuote_IfNotEnoughBalance(
        uint256 publisherProfileId,
        uint256 publisherPubId,
        uint256 minThreshold
    ) public {
        assertEq(currency.balanceOf(address(profileOwner)), 0);

        _initialize(publisherProfileId, publisherPubId, minThreshold);

        vm.expectRevert(TokenGatedReferenceModule.NotEnoughBalance.selector);
        vm.prank(address(hub));
        tokenGatedReferenceModule.processQuote(
            Types.ProcessQuoteParams({
                profileId: profileId,
                transactionExecutor: profileOwner,
                pointedProfileId: publisherProfileId,
                pointedPubId: publisherPubId,
                referrerProfileIds: _emptyUint256Array(),
                referrerPubIds: _emptyUint256Array(),
                referrerPubTypes: _emptyPubTypesArray(),
                data: ''
            })
        );
    }

    // Scenarios
    function testProcessComment_HoldingEnoughTokens(
        uint256 publisherProfileId,
        uint256 publisherPubId,
        uint256 minThreshold
    ) public {
        currency.mint(profileOwner, minThreshold);
        assertTrue(currency.balanceOf(profileOwner) >= minThreshold);

        _initialize(publisherProfileId, publisherPubId, minThreshold);

        vm.prank(address(hub));
        tokenGatedReferenceModule.processComment(
            Types.ProcessCommentParams({
                profileId: profileId,
                transactionExecutor: profileOwner,
                pointedProfileId: publisherProfileId,
                pointedPubId: publisherPubId,
                referrerProfileIds: _emptyUint256Array(),
                referrerPubIds: _emptyUint256Array(),
                referrerPubTypes: _emptyPubTypesArray(),
                data: ''
            })
        );
    }

    function testProcessMirror_HoldingEnoughTokens(
        uint256 publisherProfileId,
        uint256 publisherPubId,
        uint256 minThreshold
    ) public {
        currency.mint(profileOwner, minThreshold);
        assertTrue(currency.balanceOf(profileOwner) >= minThreshold);

        _initialize(publisherProfileId, publisherPubId, minThreshold);

        vm.prank(address(hub));
        tokenGatedReferenceModule.processMirror(
            Types.ProcessMirrorParams({
                profileId: profileId,
                transactionExecutor: profileOwner,
                pointedProfileId: publisherProfileId,
                pointedPubId: publisherPubId,
                referrerProfileIds: _emptyUint256Array(),
                referrerPubIds: _emptyUint256Array(),
                referrerPubTypes: _emptyPubTypesArray(),
                data: ''
            })
        );
    }

    function testProcessQuote_HoldingEnoughTokens(
        uint256 publisherProfileId,
        uint256 publisherPubId,
        uint256 minThreshold
    ) public {
        currency.mint(profileOwner, minThreshold);
        assertTrue(currency.balanceOf(profileOwner) >= minThreshold);

        _initialize(publisherProfileId, publisherPubId, minThreshold);

        vm.prank(address(hub));
        tokenGatedReferenceModule.processQuote(
            Types.ProcessQuoteParams({
                profileId: profileId,
                transactionExecutor: profileOwner,
                pointedProfileId: publisherProfileId,
                pointedPubId: publisherPubId,
                referrerProfileIds: _emptyUint256Array(),
                referrerPubIds: _emptyUint256Array(),
                referrerPubTypes: _emptyPubTypesArray(),
                data: ''
            })
        );
    }
}

/////////
// ERC721-Gated Reference
//
contract TokenGatedReferenceModule_ERC721_Gated is TokenGatedReferenceModuleBase {
    uint256 constant minThreshold = 1;

    function _initialize(uint256 publisherProfileId, uint256 publisherPubId) internal {
        vm.assume(publisherProfileId != 0);
        vm.assume(publisherPubId != 0);
        vm.prank(address(hub));
        tokenGatedReferenceModule.initializeReferenceModule(
            publisherProfileId,
            publisherPubId,
            address(0),
            abi.encode(GateParams({tokenAddress: address(nft), minThreshold: minThreshold}))
        );
    }

    constructor() TokenGatedReferenceModuleBase() {}

    // Negatives
    function testCannotProcessComment_IfNotEnoughBalance(uint256 publisherProfileId, uint256 publisherPubId) public {
        assertEq(nft.balanceOf(address(profileOwner)), 0);

        _initialize(publisherProfileId, publisherPubId);

        vm.expectRevert(TokenGatedReferenceModule.NotEnoughBalance.selector);
        vm.prank(address(hub));
        tokenGatedReferenceModule.processComment(
            Types.ProcessCommentParams({
                profileId: profileId,
                transactionExecutor: profileOwner,
                pointedProfileId: publisherProfileId,
                pointedPubId: publisherPubId,
                referrerProfileIds: _emptyUint256Array(),
                referrerPubIds: _emptyUint256Array(),
                referrerPubTypes: _emptyPubTypesArray(),
                data: ''
            })
        );
    }

    function testCannotProcessMirror_IfNotEnoughBalance(uint256 publisherProfileId, uint256 publisherPubId) public {
        assertEq(nft.balanceOf(address(profileOwner)), 0);

        _initialize(publisherProfileId, publisherPubId);

        vm.expectRevert(TokenGatedReferenceModule.NotEnoughBalance.selector);
        vm.prank(address(hub));
        tokenGatedReferenceModule.processMirror(
            Types.ProcessMirrorParams({
                profileId: profileId,
                transactionExecutor: profileOwner,
                pointedProfileId: publisherProfileId,
                pointedPubId: publisherPubId,
                referrerProfileIds: _emptyUint256Array(),
                referrerPubIds: _emptyUint256Array(),
                referrerPubTypes: _emptyPubTypesArray(),
                data: ''
            })
        );
    }

    function testCannotProcessQuote_IfNotEnoughBalance(uint256 publisherProfileId, uint256 publisherPubId) public {
        assertEq(nft.balanceOf(address(profileOwner)), 0);

        _initialize(publisherProfileId, publisherPubId);

        vm.expectRevert(TokenGatedReferenceModule.NotEnoughBalance.selector);
        vm.prank(address(hub));
        tokenGatedReferenceModule.processQuote(
            Types.ProcessQuoteParams({
                profileId: profileId,
                transactionExecutor: profileOwner,
                pointedProfileId: publisherProfileId,
                pointedPubId: publisherPubId,
                referrerProfileIds: _emptyUint256Array(),
                referrerPubIds: _emptyUint256Array(),
                referrerPubTypes: _emptyPubTypesArray(),
                data: ''
            })
        );
    }

    // Scenarios
    function testProcessComment_HoldingEnoughTokens(uint256 publisherProfileId, uint256 publisherPubId) public {
        nft.mint({to: profileOwner, nftId: 1});
        assertTrue(nft.balanceOf(profileOwner) >= minThreshold);

        _initialize(publisherProfileId, publisherPubId);

        vm.prank(address(hub));
        tokenGatedReferenceModule.processComment(
            Types.ProcessCommentParams({
                profileId: profileId,
                transactionExecutor: profileOwner,
                pointedProfileId: publisherProfileId,
                pointedPubId: publisherPubId,
                referrerProfileIds: _emptyUint256Array(),
                referrerPubIds: _emptyUint256Array(),
                referrerPubTypes: _emptyPubTypesArray(),
                data: ''
            })
        );
    }

    function testProcessMirror_HoldingEnoughTokens(uint256 publisherProfileId, uint256 publisherPubId) public {
        nft.mint({to: profileOwner, nftId: 1});
        assertTrue(nft.balanceOf(profileOwner) >= minThreshold);

        _initialize(publisherProfileId, publisherPubId);

        vm.prank(address(hub));
        tokenGatedReferenceModule.processMirror(
            Types.ProcessMirrorParams({
                profileId: profileId,
                transactionExecutor: profileOwner,
                pointedProfileId: publisherProfileId,
                pointedPubId: publisherPubId,
                referrerProfileIds: _emptyUint256Array(),
                referrerPubIds: _emptyUint256Array(),
                referrerPubTypes: _emptyPubTypesArray(),
                data: ''
            })
        );
    }

    function testProcessQuote_HoldingEnoughTokens(uint256 publisherProfileId, uint256 publisherPubId) public {
        nft.mint({to: profileOwner, nftId: 1});
        assertTrue(nft.balanceOf(profileOwner) >= minThreshold);

        _initialize(publisherProfileId, publisherPubId);

        vm.prank(address(hub));
        tokenGatedReferenceModule.processQuote(
            Types.ProcessQuoteParams({
                profileId: profileId,
                transactionExecutor: profileOwner,
                pointedProfileId: publisherProfileId,
                pointedPubId: publisherPubId,
                referrerProfileIds: _emptyUint256Array(),
                referrerPubIds: _emptyUint256Array(),
                referrerPubTypes: _emptyPubTypesArray(),
                data: ''
            })
        );
    }
}
