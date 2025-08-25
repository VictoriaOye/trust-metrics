# Trust Metrics

A decentralized reputation system built with Clarity smart contracts that enables users to build and track credibility across multiple domains through peer reviews, attestations, and stake-based mechanisms.

## Overview

Trust Metrics solves the reputation portability problem in decentralized systems by providing a comprehensive, cross-platform reputation scoring system. Users build reputation through peer reviews and verified attestations across different domains like freelancing, trading, gaming, and community participation.

## Quick Start

### Register as User
```clarity
;; Join with 2000 stake tokens
(contract-call? .trust-metrics register-user u2000)
```

### Submit Peer Review
```clarity
;; Review user in "freelance" domain with 85 rating
(contract-call? .trust-metrics submit-review
  'SP-USER-ADDRESS "freelance" u85 0x1234... u1500)
```

### Add Verified Attestation
```clarity
;; Add skill certification
(contract-call? .trust-metrics add-attestation
  'SP-USER-ADDRESS "solidity-expert" u95 u100 (some u52560))
```

### Check Trust Score
```clarity
;; Get comprehensive trust metrics
(contract-call? .trust-metrics calculate-trust-score
  'SP-USER-ADDRESS "freelance")
```

## Core Features

- **Multi-Domain Reputation**: Track credibility across freelance, trading, gaming, community domains
- **Stake-Weighted Reviews**: Higher stakes = more credible reviews
- **Reputation Tiers**: 5-tier system (Newcomer → Master) based on scores
- **Attestation System**: Verified credentials from trusted sources
- **Reputation Decay**: Inactive users gradually lose reputation
- **Anti-Gaming Protection**: Prevents self-reviews and spam

## Reputation Domains

| Domain | Use Case |
|--------|----------|
| `freelance` | Work quality, deliverables, communication |
| `trading` | DeFi performance, investment track record |
| `gaming` | Esports skills, NFT gaming achievements |
| `community` | Governance participation, social contribution |
| `education` | Teaching ability, knowledge sharing |

## Reputation Tiers

- **Tier 1 (0-39)**: Newcomer - Basic trust
- **Tier 2 (40-59)**: Developing - Growing reputation  
- **Tier 3 (60-74)**: Established - Solid credibility
- **Tier 4 (75-89)**: Expert - High trust level
- **Tier 5 (90-100)**: Master - Maximum credibility

## Security Features

- **Minimum Stake**: 1000 tokens required for reviews
- **No Self-Reviews**: Users cannot review themselves
- **Weight Calculation**: Review impact based on reviewer reputation + stake
- **Verified Attestations**: Owner-verified credentials boost reputation
- **Activity Decay**: 2% reputation decay for inactive users (1+ week)

## Use Cases

### Freelance Platforms
```clarity
;; Check if freelancer is trustworthy (Tier 3+)
(let ((trust-data (unwrap! (contract-call? .trust-metrics calculate-trust-score user "freelance") false)))
  (>= (get reputation-tier trust-data) u3))
```

### DeFi Protocols
```clarity
;; Verify trading reputation for lending
(contract-call? .trust-metrics get-domain-score user "trading")
```

### Gaming Platforms  
```clarity
;; Tournament eligibility based on gaming reputation
(contract-call? .trust-metrics calculate-trust-score player "gaming")
```

### DAO Governance
```clarity
;; Weight voting power by community reputation
(let ((profile (unwrap! (contract-call? .trust-metrics get-user-profile user) u0)))
  (get overall-score profile))
```

## Error Codes

- `u401` - Unauthorized access
- `u404` - User/domain not found
- `u400` - Invalid input data
- `u403` - Already reviewed this user
- `u405` - Cannot review yourself
- `u402` - Insufficient stake amount
- `u406` - Domain not found

## Functions Reference

| Function | Access | Description |
|----------|--------|-------------|
| `register-user` | Public | Join system with stake |
| `create-domain` | Owner | Add new reputation category |
| `submit-review` | Users | Provide weighted peer review |
| `add-attestation` | User/Owner | Add verified credentials |
| `calculate-trust-score` | Read-only | Get comprehensive trust metrics |
| `apply-decay-to-user` | Public | Apply reputation decay |

## Integration Examples

Cross-platform reputation verification:
```clarity
(define-read-only (verify-service-provider (user principal))
  (let ((trust-score (contract-call? .trust-metrics calculate-trust-score user "freelance")))
    (match trust-score
      ok-data (and (>= (get overall-reputation ok-data) u70)
                   (get is-verified ok-data))
      false)))
```