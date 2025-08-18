# 💧 Aquapoint - Water Usage Token System

A decentralized water utility management system built on Stacks blockchain where smart meters automatically report water usage and users pay with tokens.

## 🌊 Overview

Aquapoint revolutionizes water utility management by integrating IoT smart meters with blockchain technology. Users purchase tokens to pay for water consumption, while smart meters automatically report usage and deduct payments.

## ✨ Features

- 🏠 **Smart Meter Registration** - Register and manage water meters
- 💰 **Token-Based Payments** - Purchase and use AQUA tokens for water bills
- 📊 **Automated Usage Tracking** - Smart meters report consumption automatically  
- 📈 **Usage History** - Complete transaction and consumption records
- 🔧 **Meter Management** - Activate/deactivate meters as needed
- 👑 **Admin Controls** - Contract owner can set pricing and pause system

## 🚀 Getting Started

### Prerequisites

- [Clarinet](https://github.com/hirosystems/clarinet) installed
- Stacks wallet for testing

### Installation

```bash
clarinet new aquapoint-project
cd aquapoint-project
```

Copy the contract code to `contracts/Aquapoint.clar`

### Testing

```bash
clarinet console
```

## 📖 Usage Instructions

### For Water Consumers

1. **Purchase Tokens**
   ```clarity
   (contract-call? .Aquapoint purchase-tokens u1000)
   ```

2. **Register Smart Meter**
   ```clarity
   (contract-call? .Aquapoint register-smart-meter "METER001" "123 Main St")
   ```

3. **Check Token Balance**
   ```clarity
   (contract-call? .Aquapoint get-token-balance tx-sender)
   ```

### For Smart Meters (Automated)

1. **Report Water Usage**
   ```clarity
   (contract-call? .Aquapoint report-water-usage "METER001" u50)
   ```

### For Contract Owner

1. **Set Token Price**
   ```clarity
   (contract-call? .Aquapoint set-token-price u15)
   ```

2. **Mint Tokens for Users**
   ```clarity
   (contract-call? .Aquapoint mint-tokens 'ST1PQHQKV0RJXZFY1DGX8MNSNYVE3VGZJSRTPGZGM u500)
   ```

## 🔍 Read-Only Functions

- `get-token-balance` - Check user's token balance
- `get-meter-info` - Get smart meter details
- `get-usage-history` - View consumption history
- `get-token-price` - Current price per gallon
- `get-total-water-consumed` - System-wide consumption
- `get-user-stats` - User statistics and spending

## 💡 Contract Architecture

### Data Structures

- **Smart Meters**: Store meter info, usage, and ownership
- **User Balances**: Track tokens, spending, and meter ownership  
- **Usage History**: Complete consumption and payment records
- **Authorized Meters**: Control which meters can report usage

### Token Economics

- AQUA tokens are used for all water payments
- Price per gallon is configurable by contract owner
- Tokens are burned when water usage is reported
- Users can transfer tokens between accounts

## 🛡️ Security Features

- Only authorized meters can report usage
- Meter owners can activate/deactivate their devices
- Contract owner can pause system in emergencies
- All transactions are recorded on-chain

## 🔧 Error Codes

- `u100` - Unauthorized access
- `u101` - Insufficient token balance  
- `u102` - Invalid amount specified
- `u103` - Smart meter not found
- `u104` - Meter already registered
- `u105` - Payment failed
- `u106` - Invalid rate specified

## 🤝 Contributing

1. Fork the repository
2. Create your feature branch
3. Commit your changes
4. Push to the branch
5. Create a Pull Request

## 📄 License

This project is licensed under the MIT License.

---

Built with 💙 on Stacks blockchain

