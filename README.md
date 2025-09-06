# NFT Rental Smart Contract

A comprehensive and secure Clarity smart contract for renting NFTs on the Stacks blockchain. This contract provides a decentralized marketplace for NFT rentals with collateral protection, dispute resolution, and admin controls.

## Features

### Core Functionality
- **List NFTs for Rent**: Owners can list their NFTs with custom pricing and collateral requirements
- **Rent NFTs**: Users can rent NFTs for specified durations with automatic fee calculation
- **Collateral System**: Protects NFT owners with refundable security deposits
- **Flexible Duration**: Configurable minimum and maximum rental periods
- **Rental Extensions**: Renters can extend active rentals seamlessly

### Security Features
- **Contract Approval System**: Only admin-approved NFT contracts can be used
- **STX Escrow**: Secure collateral handling without risky NFT transfers
- **Access Controls**: Role-based permissions for all operations
- **Input Validation**: Comprehensive parameter checking
- **Emergency Functions**: Admin override capabilities for dispute resolution

### Advanced Features
- **Platform Fees**: Configurable fee system (default 2.5%)
- **User Ratings**: Reputation system for renters and owners
- **Earnings Tracking**: Track rental income for NFT owners
- **Batch Operations**: Efficient multi-NFT management
- **Real-time Status**: Comprehensive rental status tracking

## Usage

### For NFT Owners

#### 1. List NFT for Rent
```clarity
(contract-call? .nft-rental list-nft-for-rent 
  .your-nft-contract 
  u123 ;; token-id
  u100 ;; price per block (in microSTX)
  u50000 ;; collateral (in microSTX)
)
```

#### 2. Update Rental Price
```clarity
(contract-call? .nft-rental update-rental-price 
  .your-nft-contract 
  u123 
  u150 ;; new price per block
)
```

#### 3. Unlist NFT
```clarity
(contract-call? .nft-rental unlist-nft .your-nft-contract u123)
```

### For Renters

#### 1. Rent NFT
```clarity
(contract-call? .nft-rental rent-nft 
  .target-nft-contract 
  u123 ;; token-id
  u1440 ;; duration in blocks (~24 hours)
)
```

#### 2. Extend Rental
```clarity
(contract-call? .nft-rental extend-rental 
  .target-nft-contract 
  u123 
  u720 ;; additional duration in blocks
)
```

#### 3. End Rental
```clarity
(contract-call? .nft-rental end-rental .target-nft-contract u123)
```

### Query Functions

#### Check NFT Availability
```clarity
(contract-call? .nft-rental is-nft-available .nft-contract u123)
```

#### Get Rental Info
```clarity
(contract-call? .nft-rental get-rental-info .nft-contract u123)
```

#### Calculate Rental Cost
```clarity
(contract-call? .nft-rental calculate-rental-cost u100 u1440)
;; Returns: { rental-cost: u144000, platform-fee: u3600, total-cost: u147600 }
```

#### Get User Rating
```clarity
(contract-call? .nft-rental get-user-rating 'SP1234...)
```

## Admin Functions

### Approve NFT Contract
```clarity
(contract-call? .nft-rental approve-nft-contract .new-nft-contract)
```

### Set Platform Fee
```clarity
(contract-call? .nft-rental set-platform-fee-rate u300) ;; 3%
```

### Configure Duration Limits
```clarity
(contract-call? .nft-rental set-rental-duration-limits u720 u201600)
;; Min: 12 hours, Max: ~140 days
```

## Contract Architecture

### Data Structures

**Rentals Map**
```clarity
{
  owner: principal,
  renter: (optional principal),
  price-per-block: uint,
  start-block: uint,
  end-block: uint,
  collateral: uint,
  is-active: bool
}
```

**User Ratings**
```clarity
{
  total-score: uint,
  rating-count: uint
}
```

### Error Codes
- `u400`: Invalid parameters
- `u401`: Unauthorized access
- `u402`: Insufficient funds
- `u404`: Not found
- `u409`: Already exists
- `u410`: Rental expired
- `u411`: Rental active
- `u412`: NFT not available
- `u413`: Invalid contract

## Security Model

### Contract Approval
Only admin-approved NFT contracts can be used, preventing malicious contract interactions.

### Collateral Protection
- Renters deposit collateral when renting
- Returned automatically when rental ends on time
- Forfeited to owner if rental expires without return

### Access Controls
- Only rental owners can modify their listings
- Only renters can extend or end their rentals
- Only admin can approve contracts and resolve disputes

## Deployment Steps

1. Deploy the NFT rental contract
2. Approve trusted NFT contracts using `approve-nft-contract`
3. Configure platform fee and duration limits
4. Contract is ready for use

## Best Practices

### For Owners
- Set reasonable collateral amounts (typically 10-50% of NFT value)
- Price competitively based on market demand
- Respond promptly to rental requests

### For Renters
- Only rent from reputable owners
- Return NFTs promptly to recover collateral
- Rate owners to build community trust

### For Admins
- Carefully vet NFT contracts before approval
- Monitor for disputes and resolve fairly
- Adjust fees based on network conditions

## Integration

This contract can be integrated with:
- NFT marketplaces
- DeFi protocols
- Gaming platforms
- Rental aggregators

## Support

For technical issues or questions:
- Review error codes for common issues
- Check contract approval status
- Verify sufficient STX balance for transactions
- Contact admin for dispute resolution
