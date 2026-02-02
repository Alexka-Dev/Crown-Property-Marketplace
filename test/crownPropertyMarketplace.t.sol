// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/crownPropertyMarketplace.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";

/// @notice Mock NFT para pruebas
contract MockNFT is ERC721 {
    constructor() ERC721("MockNFT", "MNFT") {}

    function mint(address to_, uint256 tokenId_) external {
        _mint(to_, tokenId_);
    }
}

contract CrownPropertyMarketplaceTest is Test {
    CrownPropertyMarketplace marketplace;
    MockNFT nft;

    address deployer = makeAddr("deployer");
    address seller = makeAddr("seller");
    address buyer = makeAddr("buyer");

    uint256 constant DEFAULT_PRICE = 1 ether;
    uint256 constant TOKEN_ID = 1;

    function setUp() public {
        // Despliegue
        vm.startPrank(deployer);
        marketplace = new CrownPropertyMarketplace();
        nft = new MockNFT();
        vm.stopPrank();

        // Setup Seller
        vm.deal(seller, 100 ether);
        nft.mint(seller, TOKEN_ID);

        // Setup Buyer
        vm.deal(buyer, 1000 ether);
    }

    // ---------------------------------------------------------
    // 1. LIST PROPERTY TESTS
    // ---------------------------------------------------------

    function test_ListProperty_RevertIf_PriceIsZero() public {
        vm.startPrank(seller);
        nft.approve(address(marketplace), TOKEN_ID);

        uint fee = marketplace.listingFee();

        vm.expectRevert(
            CrownPropertyMarketplace.PriceMustBeGreaterThanZero.selector
        );
        marketplace.listProperty{value: fee}(address(nft), TOKEN_ID, 0);
        vm.stopPrank();
    }

    function test_ListProperty_RevertIf_IncorrectListingFee() public {
        vm.startPrank(seller);
        nft.approve(address(marketplace), TOKEN_ID);

        uint fee = marketplace.listingFee();

        vm.expectRevert(CrownPropertyMarketplace.IncorrectListingFee.selector);
        // Enviamos menos del fee requerido
        marketplace.listProperty{value: fee - 1}(
            address(nft),
            TOKEN_ID,
            DEFAULT_PRICE
        );
        vm.stopPrank();
    }

    function test_ListProperty_RevertIf_NotOwner() public {
        address nonOwner = makeAddr("nonOwner");
        vm.deal(nonOwner, 1 ether);

        vm.startPrank(nonOwner);

        uint fee = marketplace.listingFee();

        vm.expectRevert(CrownPropertyMarketplace.NotNFTOwner.selector);
        marketplace.listProperty{value: fee}(
            address(nft),
            TOKEN_ID,
            DEFAULT_PRICE
        );
        vm.stopPrank();
    }

    function test_ListProperty_RevertIf_NotApproved() public {
        vm.startPrank(seller);

        // We do NOT intentionally approve
        uint fee = marketplace.listingFee();

        vm.expectRevert(
            CrownPropertyMarketplace.MarketplaceNotApproved.selector
        );
        marketplace.listProperty{value: fee}(
            address(nft),
            TOKEN_ID,
            DEFAULT_PRICE
        );
        vm.stopPrank();
    }

    function test_ListProperty_Success() public {
        vm.startPrank(seller);
        nft.approve(address(marketplace), TOKEN_ID);

        vm.expectEmit(true, true, true, true);
        emit CrownPropertyMarketplace.NFTListed(
            seller,
            address(nft),
            TOKEN_ID,
            DEFAULT_PRICE
        );

        marketplace.listProperty{value: marketplace.listingFee()}(
            address(nft),
            TOKEN_ID,
            DEFAULT_PRICE
        );

        (
            address _seller,
            address _nftAddr,
            uint256 _tokenId,
            uint256 _price
        ) = marketplace.listings(address(nft), TOKEN_ID);

        assertEq(_seller, seller);
        assertEq(_nftAddr, address(nft));
        assertEq(_tokenId, TOKEN_ID);
        assertEq(_price, DEFAULT_PRICE);

        // Verificar que el fee se acumuló
        assertEq(marketplace.accumulatedFees(), marketplace.listingFee());
        vm.stopPrank();
    }

    function test_ListProperty_RevertIf_AlreadyListed() public {
        // 1. Listar correctamente
        vm.startPrank(seller);
        nft.approve(address(marketplace), TOKEN_ID);

        uint fee = marketplace.listingFee();

        marketplace.listProperty{value: fee}(
            address(nft),
            TOKEN_ID,
            DEFAULT_PRICE
        );

        // 2. Intentar listar de nuevo
        vm.expectRevert(CrownPropertyMarketplace.NFTAlreadyListed.selector);
        marketplace.listProperty{value: fee}(
            address(nft),
            TOKEN_ID,
            DEFAULT_PRICE * 2
        );
        vm.stopPrank();
    }

    // ---------------------------------------------------------
    // 2. UPDATE & CANCEL TESTS
    // ---------------------------------------------------------

    function test_CancelListing_Success() public {
        // Setup listing
        vm.startPrank(seller);
        nft.approve(address(marketplace), TOKEN_ID);
        marketplace.listProperty{value: marketplace.listingFee()}(
            address(nft),
            TOKEN_ID,
            DEFAULT_PRICE
        );

        // Cancel
        vm.expectEmit(true, true, true, true);
        emit CrownPropertyMarketplace.NFTCanceled(
            seller,
            address(nft),
            TOKEN_ID
        );

        marketplace.cancelListing(address(nft), TOKEN_ID);

        (address _seller, , , ) = marketplace.listings(address(nft), TOKEN_ID);
        assertEq(_seller, address(0)); // Debe estar borrado
        vm.stopPrank();
    }

    function test_UpdatePrice_Fuzz(uint256 newPrice) public {
        // Fuzzing: probamos con precios aleatorios
        vm.assume(newPrice > 0);

        vm.startPrank(seller);
        nft.approve(address(marketplace), TOKEN_ID);
        marketplace.listProperty{value: marketplace.listingFee()}(
            address(nft),
            TOKEN_ID,
            DEFAULT_PRICE
        );

        marketplace.updateListingPrice(address(nft), TOKEN_ID, newPrice);

        (, , , uint256 storedPrice) = marketplace.listings(
            address(nft),
            TOKEN_ID
        );
        assertEq(storedPrice, newPrice);
        vm.stopPrank();
    }

    // ---------------------------------------------------------
    // 3. BUY PROPERTY (FUZZING & MATH)
    // ---------------------------------------------------------

    /// @notice We test purchases with random prices to validate the fee calculations.
    function testFuzz_BuyProperty_EndToEnd(uint256 price) public {
        // Restricciones para evitar overflow en test o precios irreales
        price = bound(price, 0.01 ether, 100000 ether);

        // 1. Setup Listing
        vm.startPrank(seller);
        nft.approve(address(marketplace), TOKEN_ID);
        marketplace.listProperty{value: marketplace.listingFee()}(
            address(nft),
            TOKEN_ID,
            price
        );
        vm.stopPrank();

        // 2. Setup Buyer
        vm.deal(buyer, price);

        uint256 sellerBalanceBefore = seller.balance;
        uint256 feesBefore = marketplace.accumulatedFees();

        // 3. Execute Buy
        vm.prank(buyer);
        marketplace.buyProperty{value: price}(address(nft), TOKEN_ID);

        // 4. Validations
        // Protocol Fee es 1% (100 BPS)
        uint256 expectedFee = (price * 100) / 10000;
        uint256 expectedSellerAmount = price - expectedFee;

        // Check A: NFT transferido
        assertEq(nft.ownerOf(TOKEN_ID), buyer);

        // Check B: Listing borrado
        (address _seller, , , ) = marketplace.listings(address(nft), TOKEN_ID);
        assertEq(_seller, address(0));

        // Check C: Balances correctos
        assertEq(
            seller.balance,
            sellerBalanceBefore + expectedSellerAmount,
            "Seller did not receive correct amount"
        );
        assertEq(
            marketplace.accumulatedFees(),
            feesBefore + expectedFee,
            "Fees not accumulated correctly"
        );
    }

    function test_BuyProperty_RevertIf_IncorrectPayment() public {
        vm.startPrank(seller);
        nft.approve(address(marketplace), TOKEN_ID);
        marketplace.listProperty{value: marketplace.listingFee()}(
            address(nft),
            TOKEN_ID,
            DEFAULT_PRICE
        );
        vm.stopPrank();

        vm.startPrank(buyer);
        vm.expectRevert(
            CrownPropertyMarketplace.IncorrectPaymentAmount.selector
        );
        // Pagamos menos
        marketplace.buyProperty{value: DEFAULT_PRICE - 1}(
            address(nft),
            TOKEN_ID
        );
        vm.stopPrank();
    }

    function test_BuyProperty_RevertIf_NotListed() public {
        vm.startPrank(buyer);
        vm.expectRevert(CrownPropertyMarketplace.NFTNotListed.selector);
        marketplace.buyProperty{value: 1 ether}(address(nft), TOKEN_ID);
        vm.stopPrank();
    }

    // ---------------------------------------------------------
    // 4. ADMIN & FEES
    // ---------------------------------------------------------

    function test_WithdrawFees_Success() public {
        // 1. Generar fees (Listar + Vender)
        vm.startPrank(seller);
        nft.approve(address(marketplace), TOKEN_ID);
        marketplace.listProperty{value: marketplace.listingFee()}(
            address(nft),
            TOKEN_ID,
            DEFAULT_PRICE
        );
        vm.stopPrank();

        vm.prank(buyer);
        marketplace.buyProperty{value: DEFAULT_PRICE}(address(nft), TOKEN_ID);

        uint256 feesToWithdraw = marketplace.accumulatedFees();
        assertGt(feesToWithdraw, 0);

        // 2. Withdraw
        address payable treasury = payable(makeAddr("treasury"));

        vm.prank(deployer); // Owner
        marketplace.withdrawMarketplaceFees(treasury);

        assertEq(treasury.balance, feesToWithdraw);
        assertEq(marketplace.accumulatedFees(), 0);
    }

    function test_WithdrawFees_RevertIf_ZeroBalance() public {
        // Nadie ha comprado ni listado nada, fees son 0
        address payable treasury = payable(makeAddr("treasury"));

        vm.prank(deployer);
        vm.expectRevert(
            CrownPropertyMarketplace.IncorrectPaymentAmount.selector
        );
        marketplace.withdrawMarketplaceFees(treasury);
    }

    function test_UpdateListingFee_OnlyOwner() public {
        uint256 newFee = 0.5 ether;

        // Fail: User intenta
        vm.prank(seller);
        vm.expectRevert(
            abi.encodeWithSelector(
                Ownable.OwnableUnauthorizedAccount.selector,
                seller
            )
        );
        marketplace.updateListingFee(newFee);

        // Success: Owner intenta
        vm.prank(deployer);
        marketplace.updateListingFee(newFee);
        assertEq(marketplace.listingFee(), newFee);
    }
}
