// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {
    ReentrancyGuard
} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

// Interfaces para verificar aprobación sin importar todo el contrato
interface IERC721Check {
    function isApprovedForAll(
        address owner,
        address operator
    ) external view returns (bool);
    function getApproved(uint256 tokenId) external view returns (address);
}

contract CrownPropertyMarketplace is Ownable, ReentrancyGuard {
    // ---------------------------------------------------------
    // Custom Errors
    // ---------------------------------------------------------
    error PriceMustBeGreaterThanZero();
    error IncorrectListingFee();
    error NotNFTOwner();
    error NFTAlreadyListed();
    error NotListingOwner();
    error NFTNotListed();
    error IncorrectPaymentAmount();
    error TransferFailed();
    error MarketplaceNotApproved(); // Nuevo error

    // ---------------------------------------------------------
    // Types
    // ---------------------------------------------------------
    struct Listing {
        address seller;
        address nftAddress;
        uint256 tokenId;
        uint256 price;
    }

    // ---------------------------------------------------------
    // State Variables
    // ---------------------------------------------------------
    // Mapping: NFT Address -> Token ID -> Listing
    mapping(address => mapping(uint256 => Listing)) public listings;

    uint256 public listingFee = 0.01 ether; // Valor ajustado ejemplo

    // Fee del protocolo en Basis Points (100 = 1%)
    uint256 public constant PROTOCOL_FEE_BPS = 100;
    uint256 private constant BPS_DENOMINATOR = 10000;

    uint256 public accumulatedFees;

    // ---------------------------------------------------------
    // Events (PascalCase standard)
    // ---------------------------------------------------------
    event NFTListed(
        address indexed seller,
        address indexed nftAddress,
        uint256 indexed tokenId,
        uint256 price
    );

    event NFTSold(
        address indexed seller,
        address indexed buyer,
        address indexed nftAddress,
        uint256 tokenId,
        uint256 price,
        uint256 feeAmount
    );

    event NFTCanceled(
        address indexed seller,
        address indexed nftAddress,
        uint256 indexed tokenId
    );

    event ListingFeeUpdated(uint256 newFee);

    event ListingPriceUpdated(
        address indexed seller,
        address indexed nftAddress,
        uint256 indexed tokenId,
        uint256 newPrice
    );

    constructor() Ownable(msg.sender) {}

    // ---------------------------------------------------------
    // CORE LOGIC
    // ---------------------------------------------------------

    function listProperty(
        address nftAddress_,
        uint256 tokenId_,
        uint256 price_
    ) external payable nonReentrant {
        if (price_ == 0) revert PriceMustBeGreaterThanZero();
        if (msg.value != listingFee) revert IncorrectListingFee();

        // Verificamos propiedad real
        IERC721 token = IERC721(nftAddress_);
        if (token.ownerOf(tokenId_) != msg.sender) revert NotNFTOwner();

        // MEJORA: Verificar si el contrato tiene permiso para mover el NFT
        // Esto previene listados "rotos" donde el usuario pagó el fee pero no aprobó el token.
        bool isApproved = token.isApprovedForAll(msg.sender, address(this)) ||
            token.getApproved(tokenId_) == address(this);

        if (!isApproved) revert MarketplaceNotApproved();

        if (listings[nftAddress_][tokenId_].price != 0)
            revert NFTAlreadyListed();

        listings[nftAddress_][tokenId_] = Listing({
            seller: msg.sender,
            nftAddress: nftAddress_,
            tokenId: tokenId_,
            price: price_
        });

        // Acumular el listing fee inmediatamente
        accumulatedFees += msg.value;

        emit NFTListed(msg.sender, nftAddress_, tokenId_, price_);
    }

    function cancelListing(
        address nftAddress_,
        uint256 tokenId_
    ) external nonReentrant {
        Listing memory listedItem = listings[nftAddress_][tokenId_];

        // Optimización: Chequear existencia antes de leer todo el struct ahorra poco,
        // pero verificar el seller ya implica existencia.
        if (listedItem.seller != msg.sender) revert NotListingOwner();

        delete listings[nftAddress_][tokenId_];

        emit NFTCanceled(msg.sender, nftAddress_, tokenId_);
    }

    function updateListingPrice(
        address nftAddress_,
        uint256 tokenId_,
        uint256 newPrice_
    ) external {
        if (newPrice_ == 0) revert PriceMustBeGreaterThanZero();

        // Usamos storage para modificar el valor directamente
        Listing storage listedItem = listings[nftAddress_][tokenId_];

        if (listedItem.seller != msg.sender) revert NotListingOwner();

        listedItem.price = newPrice_;

        emit ListingPriceUpdated(msg.sender, nftAddress_, tokenId_, newPrice_);
    }

    function buyProperty(
        address nftAddress_,
        uint256 tokenId_
    ) external payable nonReentrant {
        // Leemos de memoria para ahorrar gas en lecturas repetidas,
        // pero necesitamos borrar del storage.
        Listing memory listedItem = listings[nftAddress_][tokenId_];

        if (listedItem.price == 0) revert NFTNotListed();
        if (msg.value != listedItem.price) revert IncorrectPaymentAmount();

        // 1. Efectos (Borrar listing para prevenir reentrancia lógica)
        delete listings[nftAddress_][tokenId_];

        // 2. Cálculo de Fees
        // Usamos math simple: Marketplace recibe X%, Seller recibe Resto.
        uint256 protocolFee = (msg.value * PROTOCOL_FEE_BPS) / BPS_DENOMINATOR;
        uint256 sellerAmount = msg.value - protocolFee;

        accumulatedFees += protocolFee;

        // 3. Interacciones

        // A. Transferir NFT al comprador
        // Usamos safeTransferFrom. Si el receiver es un contrato malicioso, podría reentrar,
        // pero ya borramos el listing (State update) y usamos nonReentrant.
        IERC721(nftAddress_).safeTransferFrom(
            listedItem.seller,
            msg.sender,
            listedItem.tokenId
        );

        // B. Pagar al vendedor
        // NOTA: Si el vendedor es un contrato que revierte al recibir ETH, la venta fallará.
        // En mercados avanzados se usa patrón "Pull" (crédito interno), pero para MVP esto es aceptable.
        (bool success, ) = listedItem.seller.call{value: sellerAmount}("");
        if (!success) revert TransferFailed();

        emit NFTSold(
            listedItem.seller,
            msg.sender,
            listedItem.nftAddress,
            listedItem.tokenId,
            listedItem.price,
            protocolFee
        );
    }

    // ---------------------------------------------------------
    // ADMIN FUNCTIONS
    // ---------------------------------------------------------
    function updateListingFee(uint256 newFee_) external onlyOwner {
        listingFee = newFee_;
        emit ListingFeeUpdated(newFee_);
    }

    function withdrawMarketplaceFees(address payable _to) external onlyOwner {
        uint256 amount = accumulatedFees;
        if (amount == 0) revert IncorrectPaymentAmount();

        accumulatedFees = 0;

        (bool success, ) = _to.call{value: amount}("");
        if (!success) revert TransferFailed();
    }
}
