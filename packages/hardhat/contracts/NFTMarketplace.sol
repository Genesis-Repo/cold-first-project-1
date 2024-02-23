// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract NFTMarketplace is ERC721Holder, Ownable {
    uint256 public feePercentage;   // Fee percentage to be set by the marketplace owner
    uint256 private constant PERCENTAGE_BASE = 100;

    struct Listing {
        address seller;
        uint256 price;
        bool isActive;
        uint256 auctionEndTime; // End time of the auction
        address highestBidder;
        uint256 highestBid;
    }

    mapping(address => mapping(uint256 => Listing)) private listings;

    event NFTListed(address indexed seller, uint256 indexed tokenId, uint256 price);
    event NFTSold(address indexed seller, address indexed buyer, uint256 indexed tokenId, uint256 price);
    event NFTPriceChanged(address indexed seller, uint256 indexed tokenId, uint256 newPrice);
    event NFTUnlisted(address indexed seller, uint256 indexed tokenId);
    event AuctionStarted(address indexed seller, uint256 indexed tokenId, uint256 startPrice, uint256 endTime);
    event NewBid(address indexed bidder, uint256 indexed tokenId, uint256 amount);
    event AuctionEnded(address indexed seller, address indexed winner, uint256 indexed tokenId, uint256 amount);

    // Other existing functions remain the same

    // Function to start an auction for an NFT
    function startAuction(address nftContract, uint256 tokenId, uint256 startPrice, uint256 duration) external {
        require(duration > 0, "Auction duration must be greater than zero");

        Listing storage listing = listings[nftContract][tokenId];
        require(!listing.isActive, "NFT is already listed for direct sale");

        // Transfer the NFT from the seller to the marketplace contract
        IERC721(nftContract).safeTransferFrom(msg.sender, address(this), tokenId);

        // Start the auction
        listing = Listing({
            seller: msg.sender,
            price: startPrice,
            isActive: false,
            auctionEndTime: block.timestamp + duration,
            highestBidder: address(0),
            highestBid: 0
        });

        emit AuctionStarted(msg.sender, tokenId, startPrice, listing.auctionEndTime);
    }

    // Function for users to place a bid in the auction
    function placeBid(address nftContract, uint256 tokenId) external payable {
        Listing storage listing = listings[nftContract][tokenId];
        require(listing.isActive == false, "Direct sale is not allowed for this NFT");
        require(block.timestamp < listing.auctionEndTime, "Auction has ended");
        require(msg.value > listing.highestBid, "Bid amount must be higher than current highest bid");

        // Return funds to the previous highest bidder
        if (listing.highestBidder != address(0)) {
            payable(listing.highestBidder).transfer(listing.highestBid);
        }

        listing.highestBidder = msg.sender;
        listing.highestBid = msg.value;

        emit NewBid(msg.sender, tokenId, msg.value);
    }

    // Function to end the auction and transfer NFT to the highest bidder
    function endAuction(address nftContract, uint256 tokenId) external {
        Listing storage listing = listings[nftContract][tokenId];
        require(block.timestamp >= listing.auctionEndTime, "Auction is still running");

        // Transfer the NFT to the highest bidder
        IERC721(nftContract).safeTransferFrom(address(this), listing.highestBidder, tokenId);

        // Calculate and transfer the fee to the marketplace owner
        uint256 feeAmount = (listing.highestBid * feePercentage) / PERCENTAGE_BASE;
        uint256 sellerAmount = listing.highestBid - feeAmount;
        payable(owner()).transfer(feeAmount); // Transfer fee to marketplace owner
        payable(listing.seller).transfer(sellerAmount); // Transfer the remaining amount to the seller

        // End the auction
        delete listings[nftContract][tokenId];

        emit AuctionEnded(listing.seller, listing.highestBidder, tokenId, listing.highestBid);
    }
}