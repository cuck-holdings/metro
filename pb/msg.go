package pb

import (
	sdk "github.com/cosmos/cosmos-sdk/types"
)

var _ sdk.Msg = &SequencerMsg{}

func NewSequencerMsg(chainID, data []byte, fromAddr sdk.AccAddress) *SequencerMsg {
	return &SequencerMsg{
		ChainId:     chainID,
		Data:        data,
		FromAddress: fromAddr.String(),
	}
}

func (*SequencerMsg) Route() string { return "SequencerMsg" }
func (*SequencerMsg) ValidateBasic() error {
	return nil
}
func (m *SequencerMsg) GetSigners() []sdk.AccAddress {
	fromAddress, _ := sdk.AccAddressFromBech32(m.FromAddress)
	return []sdk.AccAddress{fromAddress}
}
func (m *SequencerMsg) XXX_MessageName() string {
	return "SequencerMsg"
}
