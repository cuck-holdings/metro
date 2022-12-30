package consts

import (
	sdkmath "cosmossdk.io/math"
	sdk "github.com/cosmos/cosmos-sdk/types"
)

const (
	AccountAddressPrefix = "metro"
	Name                 = "metro"
	// BondDenom defines the native staking token denomination.
	BondDenom = "utick"
	// BondDenomAlias defines an alias for BondDenom.
	BondDenomAlias = "microtick"
	// DisplayDenom defines the name, symbol, and display value of the Celestia token.
	DisplayDenom = "TICK"
)

func NativeDenom(amount sdkmath.Int) sdk.Coin {
	return sdk.NewCoin(BondDenom, amount)
}
