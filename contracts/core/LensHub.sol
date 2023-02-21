// SPDX-License-Identifier: MIT

pragma solidity 0.8.15;

import {IFollowNFT} from '../interfaces/IFollowNFT.sol';
import {ILensNFTBase} from '../interfaces/ILensNFTBase.sol';
import {ILensHub} from '../interfaces/ILensHub.sol';

import {Events} from '../libraries/Events.sol';
import {DataTypes} from '../libraries/DataTypes.sol';
import {Errors} from '../libraries/Errors.sol';
import {GeneralLib} from '../libraries/GeneralLib.sol';
import {GeneralHelpers} from '../libraries/helpers/GeneralHelpers.sol';
import {ProfileLib} from '../libraries/ProfileLib.sol';
import {PublishingLib} from '../libraries/PublishingLib.sol';
import {ProfileTokenURILogic} from '../libraries/ProfileTokenURILogic.sol';
import '../libraries/Constants.sol';

import {LensNFTBase} from './base/LensNFTBase.sol';
import {LensMultiState} from './base/LensMultiState.sol';
import {LensHubStorage} from './storage/LensHubStorage.sol';
import {VersionedInitializable} from '../upgradeability/VersionedInitializable.sol';
import {IERC721Enumerable} from '@openzeppelin/contracts/token/ERC721/extensions/IERC721Enumerable.sol';
import {MetaTxHelpers} from 'contracts/libraries/helpers/MetaTxHelpers.sol';

/**
 * @title LensHub
 * @author Lens Protocol
 *
 * @notice This is the main entrypoint of the Lens Protocol. It contains governance functionality as well as
 * publishing and profile interaction functionality.
 *
 * NOTE: The Lens Protocol is unique in that frontend operators need to track a potentially overwhelming
 * number of NFT contracts and interactions at once. For that reason, we've made two quirky design decisions:
 *      1. Both Follow & Collect NFTs invoke an LensHub callback on transfer with the sole purpose of emitting an event.
 *      2. Almost every event in the protocol emits the current block timestamp, reducing the need to fetch it manually.
 */
contract LensHub is LensNFTBase, VersionedInitializable, LensMultiState, LensHubStorage, ILensHub {
    uint256 internal constant REVISION = 1;

    address internal immutable FOLLOW_NFT_IMPL;
    address internal immutable COLLECT_NFT_IMPL;

    /**
     * @dev This modifier reverts if the caller is not the configured governance address.
     */
    modifier onlyGov() {
        _validateCallerIsGovernance();
        _;
    }

    /**
     * @dev The constructor sets the immutable follow & collect NFT implementations.
     *
     * @param followNFTImpl The follow NFT implementation address.
     * @param collectNFTImpl The collect NFT implementation address.
     */
    constructor(address followNFTImpl, address collectNFTImpl) {
        if (followNFTImpl == address(0)) revert Errors.InitParamsInvalid();
        if (collectNFTImpl == address(0)) revert Errors.InitParamsInvalid();
        FOLLOW_NFT_IMPL = followNFTImpl;
        COLLECT_NFT_IMPL = collectNFTImpl;
    }

    /// @inheritdoc ILensHub
    function initialize(
        string calldata name,
        string calldata symbol,
        address newGovernance
    ) external override initializer {
        super._initialize(name, symbol);
        GeneralLib.initState(DataTypes.ProtocolState.Paused);
        _setGovernance(newGovernance);
    }

    /// ***********************
    /// *****GOV FUNCTIONS*****
    /// ***********************

    /// @inheritdoc ILensHub
    function setGovernance(address newGovernance) external override onlyGov {
        _setGovernance(newGovernance);
    }

    /// @inheritdoc ILensHub
    function setEmergencyAdmin(address newEmergencyAdmin) external override onlyGov {
        GeneralLib.setEmergencyAdmin(newEmergencyAdmin);
    }

    /// @inheritdoc ILensHub
    function setState(DataTypes.ProtocolState newState) external override {
        GeneralLib.setState(newState);
    }

    ///@inheritdoc ILensHub
    function whitelistProfileCreator(address profileCreator, bool whitelist)
        external
        override
        onlyGov
    {
        _profileCreatorWhitelisted[profileCreator] = whitelist;
        emit Events.ProfileCreatorWhitelisted(profileCreator, whitelist, block.timestamp);
    }

    /// @inheritdoc ILensHub
    function whitelistFollowModule(address followModule, bool whitelist) external override onlyGov {
        _followModuleWhitelisted[followModule] = whitelist;
        emit Events.FollowModuleWhitelisted(followModule, whitelist, block.timestamp);
    }

    /// @inheritdoc ILensHub
    function whitelistReferenceModule(address referenceModule, bool whitelist)
        external
        override
        onlyGov
    {
        _referenceModuleWhitelisted[referenceModule] = whitelist;
        emit Events.ReferenceModuleWhitelisted(referenceModule, whitelist, block.timestamp);
    }

    /// @inheritdoc ILensHub
    function whitelistCollectModule(address collectModule, bool whitelist)
        external
        override
        onlyGov
    {
        _collectModuleWhitelisted[collectModule] = whitelist;
        emit Events.CollectModuleWhitelisted(collectModule, whitelist, block.timestamp);
    }

    /// *********************************
    /// *****PROFILE OWNER FUNCTIONS*****
    /// *********************************

    /// @inheritdoc ILensNFTBase
    function permit(
        address spender,
        uint256 tokenId,
        DataTypes.EIP712Signature calldata sig
    ) external override {
        GeneralLib.permit(spender, tokenId, sig);
    }

    /// @inheritdoc ILensNFTBase
    function permitForAll(
        address owner,
        address operator,
        bool approved,
        DataTypes.EIP712Signature calldata sig
    ) external override {
        GeneralLib.permitForAll(owner, operator, approved, sig);
    }

    /// @inheritdoc ILensHub
    function createProfile(DataTypes.CreateProfileData calldata vars)
        external
        override
        whenNotPaused
        returns (uint256)
    {
        unchecked {
            uint256 profileId = ++_profileCounter;
            _mint(vars.to, profileId);
            ProfileLib.createProfile(vars, profileId);
            return profileId;
        }
    }

    /// @inheritdoc ILensHub
    function setProfileMetadataURI(uint256 profileId, string calldata metadataURI)
        external
        override
        whenNotPaused
        onlyProfileOwnerOrDelegatedExecutor(msg.sender, profileId)
    {
        ProfileLib.setProfileMetadataURI(profileId, metadataURI);
    }

    /// @inheritdoc ILensHub
    function setProfileMetadataURIWithSig(
        uint256 profileId,
        string calldata metadataURI,
        DataTypes.EIP712Signature calldata signature
    )
        external
        override
        whenNotPaused
        onlyProfileOwnerOrDelegatedExecutor(signature.signer, profileId)
    {
        MetaTxHelpers.validateSetProfileMetadataURISignature(signature, profileId, metadataURI);
        ProfileLib.setProfileMetadataURI(profileId, metadataURI);
    }

    /// @inheritdoc ILensHub
    function setFollowModule(
        uint256 profileId,
        address followModule,
        bytes calldata followModuleInitData
    ) external override whenNotPaused onlyProfileOwnerOrDelegatedExecutor(msg.sender, profileId) {
        ProfileLib.setFollowModule(profileId, followModule, followModuleInitData);
    }

    /// @inheritdoc ILensHub
    function setFollowModuleWithSig(
        uint256 profileId,
        address followModule,
        bytes calldata followModuleInitData,
        DataTypes.EIP712Signature calldata signature
    )
        external
        override
        whenNotPaused
        onlyProfileOwnerOrDelegatedExecutor(signature.signer, profileId)
    {
        MetaTxHelpers.validateSetFollowModuleSignature(
            signature,
            profileId,
            followModule,
            followModuleInitData
        );
        ProfileLib.setFollowModule(profileId, followModule, followModuleInitData);
    }

    /// @inheritdoc ILensHub
    function changeDelegatedExecutorsConfig(
        uint256 delegatorProfileId,
        address[] calldata executors,
        bool[] calldata approvals,
        uint64 configNumber,
        bool switchToGivenConfig
    ) external override whenNotPaused onlyProfileOwner(msg.sender, delegatorProfileId) {
        GeneralLib.changeGivenDelegatedExecutorsConfig(
            delegatorProfileId,
            executors,
            approvals,
            configNumber,
            switchToGivenConfig
        );
    }

    function changeCurrentDelegatedExecutorsConfig(
        uint256 delegatorProfileId,
        address[] calldata executors,
        bool[] calldata approvals
    ) external override whenNotPaused onlyProfileOwner(msg.sender, delegatorProfileId) {
        GeneralLib.changeCurrentDelegatedExecutorsConfig(delegatorProfileId, executors, approvals);
    }

    /// @inheritdoc ILensHub
    function changeDelegatedExecutorsConfigWithSig(
        uint256 delegatorProfileId,
        address[] calldata executors,
        bool[] calldata approvals,
        uint64 configNumber,
        bool switchToGivenConfig,
        DataTypes.EIP712Signature calldata signature
    ) external override whenNotPaused onlyProfileOwner(signature.signer, delegatorProfileId) {
        MetaTxHelpers.validateChangeDelegatedExecutorsConfigSignature(
            signature,
            delegatorProfileId,
            executors,
            approvals,
            configNumber,
            switchToGivenConfig
        );
        GeneralLib.changeGivenDelegatedExecutorsConfig(
            delegatorProfileId,
            executors,
            approvals,
            configNumber,
            switchToGivenConfig
        );
    }

    /// @inheritdoc ILensHub
    function setProfileImageURI(uint256 profileId, string calldata imageURI)
        external
        override
        whenNotPaused
        onlyProfileOwnerOrDelegatedExecutor(msg.sender, profileId)
    {
        ProfileLib.setProfileImageURI(profileId, imageURI);
    }

    /// @inheritdoc ILensHub
    function setProfileImageURIWithSig(
        uint256 profileId,
        string calldata imageURI,
        DataTypes.EIP712Signature calldata signature
    )
        external
        override
        whenNotPaused
        onlyProfileOwnerOrDelegatedExecutor(signature.signer, profileId)
    {
        MetaTxHelpers.validateSetProfileImageURISignature(signature, profileId, imageURI);
        ProfileLib.setProfileImageURI(profileId, imageURI);
    }

    /// @inheritdoc ILensHub
    function setFollowNFTURI(uint256 profileId, string calldata followNFTURI)
        external
        override
        whenNotPaused
        onlyProfileOwnerOrDelegatedExecutor(msg.sender, profileId)
    {
        ProfileLib.setFollowNFTURI(profileId, followNFTURI);
    }

    /// @inheritdoc ILensHub
    function setFollowNFTURIWithSig(
        uint256 profileId,
        string calldata followNFTURI,
        DataTypes.EIP712Signature calldata signature
    )
        external
        override
        whenNotPaused
        onlyProfileOwnerOrDelegatedExecutor(signature.signer, profileId)
    {
        MetaTxHelpers.validateSetFollowNFTURISignature(signature, profileId, followNFTURI);
        ProfileLib.setFollowNFTURI(profileId, followNFTURI);
    }

    /// *********************************
    /// ****** PUBLISHING FUNCTIONS *****
    /// *********************************

    /// @inheritdoc ILensHub
    function post(DataTypes.PostParams calldata postParams)
        external
        override
        whenPublishingEnabled
        onlyProfileOwnerOrDelegatedExecutor(msg.sender, postParams.profileId)
        returns (uint256)
    {
        return PublishingLib.post({postParams: postParams, transactionExecutor: msg.sender});
    }

    /// @inheritdoc ILensHub
    function postWithSig(
        DataTypes.PostParams calldata postParams,
        DataTypes.EIP712Signature calldata signature
    )
        external
        override
        whenPublishingEnabled
        onlyProfileOwnerOrDelegatedExecutor(signature.signer, postParams.profileId)
        returns (uint256)
    {
        MetaTxHelpers.validatePostSignature(signature, postParams);
        return PublishingLib.post({postParams: postParams, transactionExecutor: signature.signer});
    }

    /// @inheritdoc ILensHub
    function comment(DataTypes.CommentParams calldata commentParams)
        external
        override
        whenPublishingEnabled
        onlyProfileOwnerOrDelegatedExecutor(msg.sender, commentParams.profileId)
        onlyValidPointedPub(commentParams.pointedProfileId, commentParams.pointedPubId)
        whenNotBlocked(commentParams.profileId, commentParams.pointedProfileId)
        returns (uint256)
    {
        return
            PublishingLib.comment({commentParams: commentParams, transactionExecutor: msg.sender});
    }

    /// @inheritdoc ILensHub
    function commentWithSig(
        DataTypes.CommentParams calldata commentParams,
        DataTypes.EIP712Signature calldata signature
    )
        external
        override
        whenPublishingEnabled
        onlyProfileOwnerOrDelegatedExecutor(signature.signer, commentParams.profileId)
        onlyValidPointedPub(commentParams.pointedProfileId, commentParams.pointedPubId)
        whenNotBlocked(commentParams.profileId, commentParams.pointedProfileId)
        returns (uint256)
    {
        MetaTxHelpers.validateCommentSignature(signature, commentParams);
        return
            PublishingLib.comment({
                commentParams: commentParams,
                transactionExecutor: signature.signer
            });
    }

    /// @inheritdoc ILensHub
    function mirror(DataTypes.MirrorParams calldata mirrorParams)
        external
        override
        whenPublishingEnabled
        onlyProfileOwnerOrDelegatedExecutor(msg.sender, mirrorParams.profileId)
        onlyValidPointedPub(mirrorParams.pointedProfileId, mirrorParams.pointedPubId)
        whenNotBlocked(mirrorParams.profileId, mirrorParams.pointedProfileId)
        returns (uint256)
    {
        return PublishingLib.mirror({mirrorParams: mirrorParams, transactionExecutor: msg.sender});
    }

    /// @inheritdoc ILensHub
    function mirrorWithSig(
        DataTypes.MirrorParams calldata mirrorParams,
        DataTypes.EIP712Signature calldata signature
    )
        external
        override
        whenPublishingEnabled
        onlyProfileOwnerOrDelegatedExecutor(signature.signer, mirrorParams.profileId)
        onlyValidPointedPub(mirrorParams.pointedProfileId, mirrorParams.pointedPubId)
        whenNotBlocked(mirrorParams.profileId, mirrorParams.pointedProfileId)
        returns (uint256)
    {
        MetaTxHelpers.validateMirrorSignature(signature, mirrorParams);
        return
            PublishingLib.mirror({
                mirrorParams: mirrorParams,
                transactionExecutor: signature.signer
            });
    }

    /// @inheritdoc ILensHub
    function quote(DataTypes.QuoteParams calldata quoteParams)
        external
        override
        whenPublishingEnabled
        onlyProfileOwnerOrDelegatedExecutor(msg.sender, quoteParams.profileId)
        onlyValidPointedPub(quoteParams.pointedProfileId, quoteParams.pointedPubId)
        whenNotBlocked(quoteParams.profileId, quoteParams.pointedProfileId)
        returns (uint256)
    {
        return PublishingLib.quote({quoteParams: quoteParams, transactionExecutor: msg.sender});
    }

    /// @inheritdoc ILensHub
    function quoteWithSig(
        DataTypes.QuoteParams calldata quoteParams,
        DataTypes.EIP712Signature calldata signature
    )
        external
        override
        whenPublishingEnabled
        onlyProfileOwnerOrDelegatedExecutor(signature.signer, quoteParams.profileId)
        onlyValidPointedPub(quoteParams.pointedProfileId, quoteParams.pointedPubId)
        whenNotBlocked(quoteParams.profileId, quoteParams.pointedProfileId)
        returns (uint256)
    {
        MetaTxHelpers.validateQuoteSignature(signature, quoteParams);
        return
            PublishingLib.quote({quoteParams: quoteParams, transactionExecutor: signature.signer});
    }

    /**
     * @notice Burns a profile, this maintains the profile data struct.
     */
    function burn(uint256 tokenId)
        public
        override
        whenNotPaused
        onlyProfileOwner(msg.sender, tokenId)
    {
        _burn(tokenId);
    }

    /**
     * @notice Burns a profile with a signature, this maintains the profile data struct.
     */
    function burnWithSig(uint256 tokenId, DataTypes.EIP712Signature calldata signature)
        public
        override
        whenNotPaused
        onlyProfileOwner(signature.signer, tokenId)
    {
        MetaTxHelpers.validateBurnSignature(signature, tokenId);
        _burn(tokenId);
    }

    /// ***************************************
    /// *****PROFILE INTERACTION FUNCTIONS*****
    /// ***************************************

    /// @inheritdoc ILensHub
    function follow(
        uint256 followerProfileId,
        uint256[] calldata idsOfProfilesToFollow,
        uint256[] calldata followTokenIds,
        bytes[] calldata datas
    )
        external
        override
        whenNotPaused
        onlyProfileOwnerOrDelegatedExecutor(msg.sender, followerProfileId)
        returns (uint256[] memory)
    {
        return
            GeneralLib.follow({
                followerProfileId: followerProfileId,
                idsOfProfilesToFollow: idsOfProfilesToFollow,
                followTokenIds: followTokenIds,
                followModuleDatas: datas,
                transactionExecutor: msg.sender
            });
    }

    /// @inheritdoc ILensHub
    function followWithSig(
        uint256 followerProfileId,
        uint256[] calldata idsOfProfilesToFollow,
        uint256[] calldata followTokenIds,
        bytes[] calldata datas,
        DataTypes.EIP712Signature calldata signature
    )
        external
        override
        whenNotPaused
        onlyProfileOwnerOrDelegatedExecutor(signature.signer, followerProfileId)
        returns (uint256[] memory)
    {
        MetaTxHelpers.validateFollowSignature(
            signature,
            followerProfileId,
            idsOfProfilesToFollow,
            followTokenIds,
            datas
        );
        return
            GeneralLib.follow({
                followerProfileId: followerProfileId,
                idsOfProfilesToFollow: idsOfProfilesToFollow,
                followTokenIds: followTokenIds,
                followModuleDatas: datas,
                transactionExecutor: signature.signer
            });
    }

    /// @inheritdoc ILensHub
    function unfollow(uint256 unfollowerProfileId, uint256[] calldata idsOfProfilesToUnfollow)
        external
        override
        whenNotPaused
        onlyProfileOwnerOrDelegatedExecutor(msg.sender, unfollowerProfileId)
    {
        return
            GeneralLib.unfollow({
                unfollowerProfileId: unfollowerProfileId,
                idsOfProfilesToUnfollow: idsOfProfilesToUnfollow,
                transactionExecutor: msg.sender
            });
    }

    /// @inheritdoc ILensHub
    function unfollowWithSig(
        uint256 unfollowerProfileId,
        uint256[] calldata idsOfProfilesToUnfollow,
        DataTypes.EIP712Signature calldata signature
    )
        external
        override
        whenNotPaused
        onlyProfileOwnerOrDelegatedExecutor(signature.signer, unfollowerProfileId)
    {
        MetaTxHelpers.validateUnfollowSignature(
            signature,
            unfollowerProfileId,
            idsOfProfilesToUnfollow
        );

        return
            GeneralLib.unfollow({
                unfollowerProfileId: unfollowerProfileId,
                idsOfProfilesToUnfollow: idsOfProfilesToUnfollow,
                transactionExecutor: signature.signer
            });
    }

    /// @inheritdoc ILensHub
    function setBlockStatus(
        uint256 byProfileId,
        uint256[] calldata idsOfProfilesToSetBlockStatus,
        bool[] calldata blockStatus
    ) external override whenNotPaused onlyProfileOwnerOrDelegatedExecutor(msg.sender, byProfileId) {
        return GeneralLib.setBlockStatus(byProfileId, idsOfProfilesToSetBlockStatus, blockStatus);
    }

    /// @inheritdoc ILensHub
    function setBlockStatusWithSig(
        uint256 byProfileId,
        uint256[] calldata idsOfProfilesToSetBlockStatus,
        bool[] calldata blockStatus,
        DataTypes.EIP712Signature calldata signature
    )
        external
        override
        whenNotPaused
        onlyProfileOwnerOrDelegatedExecutor(signature.signer, byProfileId)
    {
        MetaTxHelpers.validateSetBlockStatusSignature(
            signature,
            byProfileId,
            idsOfProfilesToSetBlockStatus,
            blockStatus
        );
        return GeneralLib.setBlockStatus(byProfileId, idsOfProfilesToSetBlockStatus, blockStatus);
    }

    /// TODO: Inherit natspec
    function collect(DataTypes.CollectParams calldata collectParams)
        external
        override
        whenNotPaused
        onlyProfileOwnerOrDelegatedExecutor(msg.sender, collectParams.collectorProfileId)
        whenNotBlocked(
            collectParams.collectorProfileId,
            collectParams.publicationCollectedProfileId
        )
        returns (uint256)
    {
        return GeneralLib.collect(collectParams, msg.sender, COLLECT_NFT_IMPL); // TODO: Think how we can not pass this
    }

    /// @inheritdoc ILensHub
    function collectWithSig(
        DataTypes.CollectParams calldata collectParams,
        DataTypes.EIP712Signature calldata signature
    )
        external
        override
        whenNotPaused
        onlyProfileOwnerOrDelegatedExecutor(signature.signer, collectParams.collectorProfileId)
        whenNotBlocked(
            collectParams.collectorProfileId,
            collectParams.publicationCollectedProfileId
        )
        returns (uint256)
    {
        MetaTxHelpers.validateCollectSignature(signature, collectParams);
        return GeneralLib.collect(collectParams, signature.signer, COLLECT_NFT_IMPL);
    }

    /// @inheritdoc ILensHub
    function emitFollowNFTTransferEvent(
        uint256 profileId,
        uint256 followNFTId,
        address from,
        address to
    ) external override {
        address expectedFollowNFT = _profileById[profileId].followNFT;
        if (msg.sender != expectedFollowNFT) revert Errors.CallerNotFollowNFT();
        emit Events.FollowNFTTransferred(profileId, followNFTId, from, to, block.timestamp);
    }

    /// @inheritdoc ILensHub
    function emitCollectNFTTransferEvent(
        uint256 profileId,
        uint256 pubId,
        uint256 collectNFTId,
        address from,
        address to
    ) external override {
        address expectedCollectNFT = _pubByIdByProfile[profileId][pubId].collectNFT;
        if (msg.sender != expectedCollectNFT) revert Errors.CallerNotCollectNFT();
        emit Events.CollectNFTTransferred(
            profileId,
            pubId,
            collectNFTId,
            from,
            to,
            block.timestamp
        );
    }

    /// @inheritdoc ILensHub
    function emitUnfollowedEvent(uint256 unfollowerProfileId, uint256 idOfProfileUnfollowed)
        external
        override
    {
        address expectedFollowNFT = _profileById[idOfProfileUnfollowed].followNFT;
        if (msg.sender != expectedFollowNFT) {
            revert Errors.CallerNotFollowNFT();
        }
        emit Events.Unfollowed(unfollowerProfileId, idOfProfileUnfollowed, block.timestamp);
    }

    /// *********************************
    /// *****EXTERNAL VIEW FUNCTIONS*****
    /// *********************************

    function isFollowing(uint256 followerProfileId, uint256 followedProfileId)
        external
        view
        returns (bool)
    {
        address followNFT = _profileById[followedProfileId].followNFT;
        return followNFT != address(0) && IFollowNFT(followNFT).isFollowing(followerProfileId);
    }

    /// @inheritdoc ILensHub
    function isProfileCreatorWhitelisted(address profileCreator)
        external
        view
        override
        returns (bool)
    {
        return _profileCreatorWhitelisted[profileCreator];
    }

    /// @inheritdoc ILensHub
    function isFollowModuleWhitelisted(address followModule) external view override returns (bool) {
        return _followModuleWhitelisted[followModule];
    }

    /// @inheritdoc ILensHub
    function isReferenceModuleWhitelisted(address referenceModule)
        external
        view
        override
        returns (bool)
    {
        return _referenceModuleWhitelisted[referenceModule];
    }

    /// @inheritdoc ILensHub
    function isCollectModuleWhitelisted(address collectModule)
        external
        view
        override
        returns (bool)
    {
        return _collectModuleWhitelisted[collectModule];
    }

    /// @inheritdoc ILensHub
    function getGovernance() external view override returns (address) {
        return _governance;
    }

    /// @inheritdoc ILensHub
    function isDelegatedExecutorApproved(
        uint256 delegatorProfileId,
        address executor,
        uint64 configNumber
    ) external view returns (bool) {
        return
            GeneralHelpers.getDelegatedExecutorsConfig(delegatorProfileId).isApproved[configNumber][
                executor
            ];
    }

    /// @inheritdoc ILensHub
    function isDelegatedExecutorApproved(uint256 delegatorProfileId, address executor)
        external
        view
        returns (bool)
    {
        return GeneralHelpers.isExecutorApproved(delegatorProfileId, executor);
    }

    /// @inheritdoc ILensHub
    function getDelegatedExecutorsConfigNumber(uint256 delegatorProfileId)
        external
        view
        returns (uint64)
    {
        return GeneralHelpers.getDelegatedExecutorsConfig(delegatorProfileId).configNumber;
    }

    /// @inheritdoc ILensHub
    function getDelegatedExecutorsPrevConfigNumber(uint256 delegatorProfileId)
        external
        view
        returns (uint64)
    {
        return GeneralHelpers.getDelegatedExecutorsConfig(delegatorProfileId).prevConfigNumber;
    }

    /// @inheritdoc ILensHub
    function getDelegatedExecutorsMaxConfigNumberSet(uint256 delegatorProfileId)
        external
        view
        returns (uint64)
    {
        return GeneralHelpers.getDelegatedExecutorsConfig(delegatorProfileId).maxConfigNumberSet;
    }

    /// @inheritdoc ILensHub
    function isBlocked(uint256 profileId, uint256 byProfileId) external view returns (bool) {
        return _blockedStatus[byProfileId][profileId];
    }

    /// @inheritdoc ILensHub
    function getProfileMetadataURI(uint256 profileId)
        external
        view
        override
        returns (string memory)
    {
        return _metadataByProfile[profileId];
    }

    /// @inheritdoc ILensHub
    function getPubCount(uint256 profileId) external view override returns (uint256) {
        return _profileById[profileId].pubCount;
    }

    /// @inheritdoc ILensHub
    function getProfileImageURI(uint256 profileId) external view override returns (string memory) {
        return _profileById[profileId].imageURI;
    }

    /// @inheritdoc ILensHub
    function getFollowNFT(uint256 profileId) external view override returns (address) {
        return _profileById[profileId].followNFT;
    }

    /// @inheritdoc ILensHub
    function getFollowNFTURI(uint256 profileId) external view override returns (string memory) {
        return _profileById[profileId].followNFTURI;
    }

    /// @inheritdoc ILensHub
    function getCollectNFT(uint256 profileId, uint256 pubId)
        external
        view
        override
        returns (address)
    {
        return _pubByIdByProfile[profileId][pubId].collectNFT;
    }

    /// @inheritdoc ILensHub
    function getFollowModule(uint256 profileId) external view override returns (address) {
        return _profileById[profileId].followModule;
    }

    /// @inheritdoc ILensHub
    function getCollectModule(uint256 profileId, uint256 pubId)
        external
        view
        override
        returns (address)
    {
        return _pubByIdByProfile[profileId][pubId].collectModule;
    }

    /// @inheritdoc ILensHub
    function getReferenceModule(uint256 profileId, uint256 pubId)
        external
        view
        override
        returns (address)
    {
        return _pubByIdByProfile[profileId][pubId].referenceModule;
    }

    /// @inheritdoc ILensHub
    function getPubPointer(uint256 profileId, uint256 pubId)
        external
        view
        override
        returns (uint256, uint256)
    {
        uint256 pointedProfileId = _pubByIdByProfile[profileId][pubId].pointedProfileId;
        uint256 pointedPubId = _pubByIdByProfile[profileId][pubId].pointedPubId;
        return (pointedProfileId, pointedPubId);
    }

    /// @inheritdoc ILensHub
    function getContentURI(uint256 profileId, uint256 pubId)
        external
        view
        override
        returns (string memory)
    {
        return GeneralLib.getContentURI(profileId, pubId);
    }

    /// @inheritdoc ILensHub
    function getProfile(uint256 profileId)
        external
        view
        override
        returns (DataTypes.ProfileStruct memory)
    {
        return _profileById[profileId];
    }

    /// @inheritdoc ILensHub
    function getPub(uint256 profileId, uint256 pubId)
        external
        view
        override
        returns (DataTypes.PublicationStruct memory)
    {
        return _pubByIdByProfile[profileId][pubId];
    }

    /// @inheritdoc ILensHub
    function getPublicationType(uint256 profileId, uint256 pubId)
        external
        view
        override
        returns (DataTypes.PublicationType)
    {
        return GeneralHelpers.getPublicationType(profileId, pubId);
    }

    /// @inheritdoc ILensHub
    function getFollowNFTImpl() external view override returns (address) {
        return FOLLOW_NFT_IMPL;
    }

    /// @inheritdoc ILensHub
    function getCollectNFTImpl() external view override returns (address) {
        return COLLECT_NFT_IMPL;
    }

    /**
     * @dev Overrides the LensNFTBase function to compute the domain separator in the GeneralLib.
     */
    function getDomainSeparator() external view override returns (bytes32) {
        return GeneralLib.getDomainSeparator();
    }

    /**
     * @dev Overrides the ERC721 tokenURI function to return the associated URI with a given profile.
     */
    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        address followNFT = _profileById[tokenId].followNFT;
        return
            ProfileTokenURILogic.getProfileTokenURI(
                tokenId,
                followNFT == address(0) ? 0 : IERC721Enumerable(followNFT).totalSupply(),
                ownerOf(tokenId),
                'Lens Profile',
                _profileById[tokenId].imageURI
            );
    }

    /// ****************************
    /// *****INTERNAL FUNCTIONS*****
    /// ****************************

    function _setGovernance(address newGovernance) internal {
        GeneralLib.setGovernance(newGovernance);
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId
    ) internal override whenNotPaused {
        // Switches to new fresh delegated executors configuration (except on minting, as it already has a fresh setup).
        if (from != address(0)) {
            GeneralLib.switchToNewFreshDelegatedExecutorsConfig(tokenId);
        }
        super._beforeTokenTransfer(from, to, tokenId);
    }

    function _validateCallerIsGovernance() internal view {
        if (msg.sender != _governance) revert Errors.NotGovernance();
    }

    function getRevision() internal pure virtual override returns (uint256) {
        return REVISION;
    }
}
