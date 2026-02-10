# 🍽️ Decentralized Catering Co-Op

A blockchain-powered DAO that enables small catering businesses to pool their resources and bid on large contracts they couldn't secure individually.

## 🌟 Features

- **💰 Member Contributions**: Join the co-op by contributing STX tokens
- **📋 Proposal System**: Create proposals for new catering contracts
- **🗳️ Democratic Voting**: Vote on proposals using contribution-based voting power
- **🏆 Competitive Bidding**: Submit bids for approved contracts
- **👨‍🍳 Caterer Profiles**: Maintain professional profiles with specialties and ratings
- **⭐ Rating System**: Rate caterers based on performance
- **🏦 Treasury Management**: Automated fund distribution for selected bids

## 🚀 Getting Started

### Prerequisites
- [Clarinet](https://github.com/hirosystems/clarinet) installed
- STX tokens for participation

### Installation
```bash
git clone https://github.com/your-repo/decentralized-catering-co-op
cd decentralized-catering-co-op
clarinet check
```

## 📖 Usage Guide

### 1. 🤝 Joining the Co-Op
```clarity
(contract-call? .decentralized-catering join-coop u10000000)
```
- Minimum contribution: 1,000,000 microSTX (1 STX)
- Voting power = contribution ÷ 1000

### 2. 📝 Creating Proposals
```clarity
(contract-call? .decentralized-catering create-proposal 
    "Wedding Catering Contract" 
    "500-person wedding reception in downtown" 
    u50000000000 
    u10000000000)
```
- Only active members can create proposals
- Specify contract value and required funds

### 3. 🗳️ Voting on Proposals
```clarity
(contract-call? .decentralized-catering vote-on-proposal u1 true)
```
- Vote within the 144-block voting period
- One vote per member per proposal

### 4. ⚡ Executing Proposals
```clarity
(contract-call? .decentralized-catering execute-proposal u1)
```
- Must wait until voting period ends
- Requires minimum 50 votes (quorum)

### 5. 💼 Submitting Bids
```clarity
(contract-call? .decentralized-catering submit-bid 
    u1 
    u8000000000 
    "Full-service catering with appetizers, main course, and desserts")
```
- Only for approved proposals
- Include competitive pricing and service description

### 6. 👑 Bid Selection
```clarity
(contract-call? .decentralized-catering select-bid u1)
```
- Contract owner selects winning bids
- Automatic fund transfer to selected caterer

### 7. 👨‍🍳 Profile Management
```clarity
(contract-call? .decentralized-catering update-caterer-profile 
    "Gourmet Delights" 
    "Italian, Mediterranean, Vegan options" 
    u200)
```

### 8. ⭐ Rating System
```clarity
(contract-call? .decentralized-catering rate-caterer 'SP1234... u5)
```
- Rate caterers from 1-5 stars
- Builds reputation within the co-op

## 🔍 Read-Only Functions

### Get Member Info
```clarity
(contract-call? .decentralized-catering get-member 'SP1234...)
```

### View Proposals
```clarity
(contract-call? .decentralized-catering get-proposal u1)
```

### Check Treasury Balance
```clarity
(contract-call? .decentralized-catering get-treasury-balance)
```

### View Caterer Profiles
```clarity
(contract-call? .decentralized-catering get-caterer-profile 'SP1234...)
```

## 🏗️ Contract Architecture

### Data Structures
- **Members**: Contribution, voting power, join date, status
- **Proposals**: Contract details, voting results, execution status
- **Bids**: Caterer submissions for approved contracts
- **Caterer Profiles**: Business information and ratings

### Key Constants
- `MIN-CONTRIBUTION`: 1,000,000 microSTX minimum to join
- `VOTING-PERIOD`: 144 blocks (~24 hours)
- `MIN-QUORUM`: 50 votes required for proposal execution

## 🛡️ Security Features

- Member-only proposal creation and voting
- Time-bound voting periods
- Treasury balance validation
- One-vote-per-member enforcement
- Owner-only bid selection

## 🤝 Contributing

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## 📄 License

This project is licensed under the MIT License - see the LICENSE file for details.

## 🆘 Support

For questions or support, please open an issue in the GitHub repository.

---

*Built with ❤️ for the catering community*
