# 🏰 Crown Property Marketplace

![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)
![Solidity](https://img.shields.io/badge/Solidity-%5E0.8.20-blue)
![Foundry](https://img.shields.io/badge/Built%20with-Foundry-orange)
![Coverage](https://img.shields.io/badge/Tests-100%25-success)

**CrownPropertyMarketplace** is a decentralized platform for trading property NFTs, prioritizing security through the **CEI** pattern and efficiency via **Custom Errors**. It enables users to list, update, and cancel sales with real-time approval verification while integrating automated **service fee** logic (1%). The system secures funds using `ReentrancyGuard` and offers the contract owner transparent management of accumulated fees.

---

## ⚡ Key Features

- **Security First:** Implements the _Checks-Effects-Interactions_ pattern and protection against reentrancy attacks.
- **Gas Optimized:** Uses `Custom Errors` instead of strings for reverting transactions, saving gas on deployment and execution.
- **Robust Validation:** Verifies `isApprovedForAll` before listing to prevent failed transactions and improve UX.
- **Fuzz Testing:** Mathematical logic for fees is tested with random values to ensure solvency under any scenario.

## 🛠️ Tech Stack

- **Language:** Solidity `^0.8.20`
- **Framework:** Foundry (Forge)
- **Standards:** OpenZeppelin (ERC721, Ownable, ReentrancyGuard)

## 🚀 Installation & Usage

### Prerequisites

Ensure you have [Foundry](https://book.getfoundry.sh/getting-started/installation) installed.

### 1. Clone the repository

````bash
git clone [https://github.com/YOUR_USERNAME/crown-property-marketplace.git](https://github.com/YOUR_USERNAME/crown-property-marketplace.git)
cd crown-property-marketplace

### 2. Install Dependencies
```bash
forge install

### 3. Build
```bash
forge build

### 🧪 Tests & Coverage
This project features an exhaustive test suite covering 100% of the contract logic, including Fuzzing tests.

### Run Tests:
```bash
forge test --match-test (test name)

### Check Coverage:
```bash
forge coverage
````
