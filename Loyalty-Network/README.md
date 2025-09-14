# Loyalty Points System Smart Contract

A comprehensive loyalty program smart contract built on the Stacks blockchain using Clarity. This contract enables merchants to issue points to customers, customers to redeem rewards, and implements a tier-based system with point expiration.

## Overview

The Loyalty Points System provides a complete solution for managing customer loyalty programs with the following key features:

- Points earning through purchases
- Tier-based system with multipliers
- Reward redemption system
- Point expiration mechanism
- Transfer capabilities between users
- Comprehensive transaction history

## Features

### Core Functionality

- **Points Earning**: Customers earn points based on STX spent with registered merchants
- **Tier System**: Four-tier loyalty system (Bronze, Silver, Gold, Platinum) with earning multipliers
- **Reward Redemption**: Catalog-based reward system with tier restrictions
- **Point Transfer**: Users can transfer points to other users
- **Expiration Management**: Automatic point expiration after configurable periods
- **Transaction History**: Complete audit trail of all point transactions

### Administrative Features

- **Merchant Management**: Register and manage merchant accounts
- **Reward Catalog**: Add and manage rewards with tier requirements
- **Contract Controls**: Pause/unpause functionality and configuration management

## Constants

### Error Codes

- `ERR-UNAUTHORIZED (u100)`: Unauthorized access
- `ERR-INSUFFICIENT-BALANCE (u101)`: Insufficient point balance
- `ERR-INVALID-AMOUNT (u102)`: Invalid amount specified
- `ERR-MERCHANT-NOT-FOUND (u103)`: Merchant does not exist
- `ERR-REWARD-NOT-FOUND (u104)`: Reward does not exist
- `ERR-INSUFFICIENT-POINTS (u105)`: Not enough points for operation
- `ERR-EXPIRED-POINTS (u106)`: Points have expired
- `ERR-TIER-NOT-FOUND (u107)`: Invalid tier specified
- `ERR-ALREADY-EXISTS (u108)`: Entity already exists
- `ERR-INVALID-PERCENTAGE (u109)`: Invalid percentage value
- `ERR-POINTS-EXPIRED (u110)`: Points are expired
- `ERR-INVALID-INPUT (u111)`: Invalid input parameters

### Tier System

- **Bronze**: 0+ lifetime points (1.0x multiplier)
- **Silver**: 1,000+ lifetime points (1.1x multiplier)
- **Gold**: 5,000+ lifetime points (1.25x multiplier)
- **Platinum**: 15,000+ lifetime points (1.5x multiplier)

## Data Structures

### User Balance
```clarity
{
  total-points: uint,           // Total points owned
  available-points: uint,       // Points available for use
  lifetime-earned: uint,        // Total points earned historically
  lifetime-redeemed: uint,      // Total points redeemed historically
  current-tier: string-ascii,   // Current tier status
  tier-progress: uint,          // Progress to next tier (0-100%)
  last-activity: uint           // Last activity block height
}
```

### Merchant Information
```clarity
{
  name: string-ascii,           // Merchant display name
  points-rate: uint,            // Points per STX (with decimals)
  is-active: bool,              // Whether merchant is active
  total-points-issued: uint     // Total points issued by merchant
}
```

### Reward Information
```clarity
{
  name: string-ascii,           // Reward name
  description: string-ascii,    // Reward description
  points-cost: uint,            // Points required for redemption
  merchant: principal,          // Issuing merchant
  is-active: bool,              // Whether reward is available
  total-redeemed: uint,         // Number of times redeemed
  tier-requirement: string-ascii // Minimum tier required
}
```

## Administrative Functions

### Merchant Management

#### `register-merchant`
Register a new merchant in the system.
```clarity
(register-merchant merchant-principal name points-rate)
```
- **Parameters**:
  - `merchant-principal`: The merchant's wallet address
  - `name`: Merchant display name (max 50 characters)
  - `points-rate`: Points earned per STX spent (with 6 decimal places)
- **Access**: Contract owner only

#### `update-merchant-status`
Enable or disable a merchant.
```clarity
(update-merchant-status merchant-principal is-active)
```
- **Parameters**:
  - `merchant-principal`: The merchant's wallet address
  - `is-active`: Boolean status
- **Access**: Contract owner only

### Reward Management

#### `add-reward`
Add a new reward to the catalog.
```clarity
(add-reward name description points-cost merchant tier-requirement)
```
- **Parameters**:
  - `name`: Reward name (max 100 characters)
  - `description`: Reward description (max 500 characters)
  - `points-cost`: Points required for redemption
  - `merchant`: Merchant offering the reward
  - `tier-requirement`: Minimum tier ("BRONZE", "SILVER", "GOLD", "PLATINUM")
- **Access**: Contract owner only
- **Returns**: Reward ID

#### `update-reward-status`
Enable or disable a reward.
```clarity
(update-reward-status reward-id is-active)
```
- **Parameters**:
  - `reward-id`: Unique reward identifier
  - `is-active`: Boolean status
- **Access**: Contract owner only

### Contract Configuration

#### `set-points-expiry-days`
Configure how long points remain valid.
```clarity
(set-points-expiry-days days)
```
- **Parameters**:
  - `days`: Number of days before points expire
- **Access**: Contract owner only

#### `set-contract-pause`
Pause or unpause the contract.
```clarity
(set-contract-pause paused)
```
- **Parameters**:
  - `paused`: Boolean pause status
- **Access**: Contract owner only

## User Functions

### Earning Points

#### `earn-points`
Merchants call this function to award points to customers.
```clarity
(earn-points user stx-amount)
```
- **Parameters**:
  - `user`: Customer's wallet address
  - `stx-amount`: Amount of STX spent
- **Access**: Registered merchants only
- **Returns**: Points awarded (includes tier multiplier)

### Redeeming Rewards

#### `redeem-reward`
Redeem points for a specific reward.
```clarity
(redeem-reward reward-id)
```
- **Parameters**:
  - `reward-id`: ID of the reward to redeem
- **Access**: Any user with sufficient points and tier
- **Requirements**: 
  - Sufficient available points
  - Meet minimum tier requirement
  - Reward must be active

### Point Transfers

#### `transfer-points`
Transfer points to another user.
```clarity
(transfer-points recipient amount)
```
- **Parameters**:
  - `recipient`: Recipient's wallet address
  - `amount`: Number of points to transfer
- **Access**: Any user with sufficient points

### Maintenance

#### `cleanup-expired-points`
Remove expired points from a user's balance.
```clarity
(cleanup-expired-points user batch-id)
```
- **Parameters**:
  - `user`: User's wallet address
  - `batch-id`: Specific batch of points to expire
- **Access**: Anyone (incentivized cleanup)

## Read-Only Functions

### User Information

#### `get-user-balance`
Retrieve complete user balance and tier information.
```clarity
(get-user-balance user-principal)
```

#### `can-redeem-reward`
Check if a user can redeem a specific reward.
```clarity
(can-redeem-reward user-principal reward-id)
```
Returns detailed eligibility information including point sufficiency and tier requirements.

### System Information

#### `get-merchant-info`
Get merchant details and statistics.
```clarity
(get-merchant-info merchant-principal)
```

#### `get-reward-info`
Get reward details and redemption statistics.
```clarity
(get-reward-info reward-id)
```

#### `get-transaction`
Retrieve transaction history by ID.
```clarity
(get-transaction transaction-id)
```

#### `get-points-expiry`
Check expiration details for a specific point batch.
```clarity
(get-points-expiry user-principal batch-id)
```

#### `get-contract-config`
Get current contract configuration.
```clarity
(get-contract-config)
```

#### `get-tier-requirements`
Get point thresholds for all tiers.
```clarity
(get-tier-requirements)
```

## Usage Examples

### Setting Up a Merchant
```clarity
;; Register a coffee shop that gives 10 points per STX
(register-merchant 'SP1234...COFFEE "Coffee Shop" u10000000)
```

### Adding a Reward
```clarity
;; Add a free coffee reward for Silver+ members
(add-reward "Free Coffee" "One free coffee of any size" u500 'SP1234...COFFEE "SILVER")
```

### Customer Earning Points
```clarity
;; Customer spends 5 STX at the coffee shop
(earn-points 'SP5678...CUSTOMER u5000000)
```

### Customer Redeeming Reward
```clarity
;; Customer redeems free coffee (reward ID 1)
(redeem-reward u1)
```

## Security Considerations

1. **Access Control**: Only contract owner can manage merchants and rewards
2. **Input Validation**: All inputs are validated for type and range
3. **Balance Checks**: Prevents negative balances and insufficient funds
4. **Tier Verification**: Enforces tier requirements for reward redemption
5. **Expiration Handling**: Automatic point expiration prevents indefinite accumulation

## Gas Optimization

The contract is optimized for gas efficiency through:
- Efficient data structures
- Minimal state changes per transaction
- Batch processing for expired points
- Optional cleanup incentivization