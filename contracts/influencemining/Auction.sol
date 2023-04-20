//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/utils/math/SafeMathUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "../IERC721H.sol";
import "./HNFTGovernance.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

contract Auction is OwnableUpgradeable {
    using SafeMathUpgradeable for uint256;

    struct Bid {
        uint256 bidId;
        uint256 amount;
        address bidder;
        string  slotUri;
    }

    struct PreBid {
        uint256 bidId;
        uint256 amount;
        address bidder;
        uint256 preBidTime;
    }

    struct HNFTInfo {
        uint256 hNFTId;
        address hNFTContractAddr;
    }


    address private relayerAddress;
    address private ad3Address;
    address private hnftGoverAddress;
    mapping(address => mapping(uint256 => Bid)) public curBid;
    mapping(address => mapping(uint256 => PreBid)) public preBids;

    uint256 private MIN_DEPOIST_FOR_PRE_BID;
    uint256 private TIMEOUT;

    function initialize(address _relayerAddress, address _ad3Address, address _hnftGoverAddress) public initializer {
        __Ownable_init();
        relayerAddress = _relayerAddress;
        ad3Address = _ad3Address;
        hnftGoverAddress = _hnftGoverAddress;
        MIN_DEPOIST_FOR_PRE_BID = 10;
        TIMEOUT = 10 minutes;
    }

    event BidPrepared(address hNFTContractAddr, uint256 indexed curBidId, uint256 indexed preBidId,  address bidder);
    event BidCommitted(address hNFTContractAddr, uint256 indexed curBidId, uint256 indexed preBidId, address bidder);
    event BidRefunded(uint256 bidId, uint256 hNFTId, address to, uint256 amount);

    function preBid(address hNFTContractAddr, uint256 hNFTId) public {
        require(hNFTId > 0, "hNFTId must be greater than 0.");
        require(block.timestamp >= preBids[hNFTContractAddr][hNFTId].preBidTime.add(TIMEOUT), "Last preBid still within the valid time");
        IERC721 hNFTContract = IERC721(hNFTContractAddr);
        require(hNFTContract.getApproved(hNFTId) == address(this), "hNFTId does not approve");
        IERC20 ad3Add = IERC20(ad3Address);
        require(ad3Add.balanceOf(_msgSender()) >= MIN_DEPOIST_FOR_PRE_BID, "AD3 balance not enough");
        require(ad3Add.allowance(_msgSender(), address(this)) >= MIN_DEPOIST_FOR_PRE_BID, "allowance not enough");
        ad3Add.transferFrom(_msgSender(), address(this), MIN_DEPOIST_FOR_PRE_BID);
        uint256 preBidId = _generateRandomNumber();
        preBids[hNFTContractAddr][hNFTId]= PreBid(preBidId, MIN_DEPOIST_FOR_PRE_BID, _msgSender(), block.timestamp);
        uint256 curBidId = curBid[hNFTContractAddr][hNFTId].bidId != 0 ? curBid[hNFTContractAddr][hNFTId].bidId : 0;

        emit BidPrepared(hNFTContractAddr ,curBidId, preBidId, _msgSender());
    }

    function commitBid(
        HNFTInfo memory hNFTInfo,
        uint256 governanceTokenAmount,
        string memory slotUri,
        bytes memory _signature,
        uint256 curBidId,
        uint256 preBidId,
        uint256 curBidRemain
    ) public {
        require(hNFTInfo.hNFTId > 0, "hNFTId must be greater than 0.");
        require(governanceTokenAmount > 0, "Bid amount must be greater than 0.");
        require(hNFTInfo.hNFTContractAddr != address(0), "The hNFT and governance contract can not be address(0).");
        require(curBidId == curBid[hNFTInfo.hNFTContractAddr][hNFTInfo.hNFTId].bidId, "Invalid curBidId");
        require(preBidId == preBids[hNFTInfo.hNFTContractAddr][hNFTInfo.hNFTId].bidId, "Invalid preBidId");
        address governanceTokenAddr = HNFTGovernance(hnftGoverAddress).getGovernanceToken(hNFTInfo.hNFTContractAddr, hNFTInfo.hNFTId);
        IERC721H hNFT = IERC721H(hNFTInfo.hNFTContractAddr);
        IERC20 token = governanceTokenAddr == address(0) ? IERC20(ad3Address) : IERC20(governanceTokenAddr);
        require(token.balanceOf(_msgSender()) >= governanceTokenAmount, "balance not enough");
        require(token.allowance(_msgSender(), address(this)) >= governanceTokenAmount, "allowance not enough");
        address _signAddress = recover(hNFTInfo.hNFTId, hNFTInfo.hNFTContractAddr, address(token), governanceTokenAmount, curBidId, preBidId, _signature);
        require(verify(_signAddress), "Invalid Signer!");
        require(_isAtLeast120Percent(curBid[hNFTInfo.hNFTContractAddr][hNFTInfo.hNFTId].amount, governanceTokenAmount), "The bid is less than 120%");
        require(_msgSender() == preBids[hNFTInfo.hNFTContractAddr][hNFTInfo.hNFTId].bidder, "Not the preBid owner");
        _processCurBid(token, governanceTokenAmount, hNFT, hNFTInfo.hNFTId, slotUri, curBidRemain);
        _refundPrevBidIfRequired(hNFTInfo.hNFTContractAddr, hNFTInfo.hNFTId, token, curBidRemain);
        
        curBid[hNFTInfo.hNFTContractAddr][hNFTInfo.hNFTId] = Bid(preBidId, governanceTokenAmount, _msgSender(), slotUri);
        emit BidCommitted(hNFTInfo.hNFTContractAddr, curBidId, preBidId, _msgSender());
    }

    function setRelayerAddress(address _relayerAddress) public onlyOwner {
        relayerAddress = _relayerAddress;
    }

    function getRelayerAddress() public onlyOwner view returns (address){
        return relayerAddress ;
    }

    function setMinDepositForPreBid (uint256 _MIN_DEPOIST_FOR_PRE_BID) public onlyOwner {
        MIN_DEPOIST_FOR_PRE_BID = _MIN_DEPOIST_FOR_PRE_BID;
    }

    function getMinDepositForPreBid () public onlyOwner view returns (uint256){
        return MIN_DEPOIST_FOR_PRE_BID;
    }

    function recover(uint256 hnftId, address hNFTContractAddr, 
                     address governanceTokenAddress, uint256 governanceTokenAmount, 
                     uint256 curBidId, uint256 preBidId, bytes memory _signature) public pure returns (address) {
        bytes32 _msgHash = ECDSA.toEthSignedMessageHash(
            genMessageHash(hnftId, hNFTContractAddr, governanceTokenAddress, governanceTokenAmount, curBidId, preBidId)
        );
        return ECDSA.recover(_msgHash, _signature);
    }

    // --- Private Function ---
    function _processCurBid(
        IERC20 token, uint256 governanceTokenAmount, 
        IERC721H hNft, uint256 hNFTId, 
        string memory slotUri, uint256 curBidRemain
    ) private {
        token.transferFrom(_msgSender(), address(this), governanceTokenAmount);
        uint256 amount = governanceTokenAmount.sub(curBidRemain);
        token.approve(relayerAddress, amount.add(token.allowance(address(this), relayerAddress)));
        hNft.setSlotUri(hNFTId, slotUri);
    }

    function _refundPrevBidIfRequired(address hNFTContractAddr, uint256 hNFTId, IERC20 token, uint256 curBidRemain) private {
        IERC20 ad3Addr = IERC20(ad3Address);
        uint256 preAmount = preBids[hNFTContractAddr][hNFTId].amount;
        delete preBids[hNFTContractAddr][hNFTId];
        ad3Addr.transfer(_msgSender(), preAmount);

        if(curBid[hNFTContractAddr][hNFTId].amount > 0) {
            Bid memory currentBid = curBid[hNFTContractAddr][hNFTId];
            token.transfer(currentBid.bidder, curBidRemain);

            emit BidRefunded(currentBid.bidId, hNFTId, currentBid.bidder, currentBid.amount);
        }
    }
    
    function _isAtLeast120Percent(uint256 lastBidAmount, uint256 bidAmount) private pure returns(bool) {
        uint256 result = lastBidAmount.mul(12).div(10);
        return bidAmount >= result;
    }

    function _generateRandomNumber() private view returns (uint256) {
        bytes32 blockHash = blockhash(block.number);
        bytes memory concatData = abi.encodePacked(blockHash, block.timestamp, block.coinbase);
        bytes32 hash = keccak256(concatData);
        return uint256(hash);
    }

    function genMessageHash(uint256 hnftId, address hNFTContractAddr, 
                            address governanceTokenAddress, uint256 governanceTokenAmount, 
                            uint256 curBidId, uint256 preBidId) private pure returns (bytes32){
        return keccak256(abi.encodePacked(hnftId, hNFTContractAddr, governanceTokenAddress, governanceTokenAmount, curBidId, preBidId));
    }

    function verify(address _signerAddress) private view returns (bool) {
        return _signerAddress == relayerAddress;
    }
}