package builder_test

import (
	"strings"
	"testing"
	"time"

	"github.com/histolabs/metro/app"
	"github.com/histolabs/metro/app/encoding"
	"github.com/histolabs/metro/pkg/builder"
	"github.com/histolabs/metro/pkg/consts"
	"github.com/histolabs/metro/testutil/testfactory"
	"github.com/histolabs/metro/testutil/testnode"
	"github.com/stretchr/testify/require"
	"github.com/stretchr/testify/suite"

	sdk "github.com/cosmos/cosmos-sdk/types"
	banktypes "github.com/cosmos/cosmos-sdk/x/bank/types"
	abci "github.com/tendermint/tendermint/abci/types"
)

func TestIntegrationTestSuite(t *testing.T) {
	suite.Run(t, new(IntegrationTestSuite))
}

type IntegrationTestSuite struct {
	suite.Suite

	cleanup  func() error
	accounts []string
	cctx     testnode.Context
	ecfg     encoding.Config
}

func (s *IntegrationTestSuite) SetupSuite() {
	if testing.Short() {
		s.T().Skip("skipping test in unit-tests or race-detector mode.")
	}

	s.T().Log("setting up integration test suite")
	cleanup, accounts, cctx := testnode.DefaultNetwork(s.T(), time.Millisecond*500)

	s.cctx = cctx
	s.accounts = accounts
	s.cleanup = cleanup

	s.ecfg = encoding.MakeConfig(app.ModuleEncodingRegisters...)
}

func (s *IntegrationTestSuite) TearDownSuite() {
	s.T().Log("tearing down integration test suite")
	err := s.cleanup()
	require.NoError(s.T(), err)
}

func (s *IntegrationTestSuite) TestPrimaryChainIDBuilder() {
	t := s.T()

	// define the tx builder options
	feeCoin := sdk.Coin{
		Denom:  consts.BondDenom,
		Amount: sdk.NewInt(1),
	}

	opts := []builder.TxBuilderOption{
		builder.SetFeeAmount(sdk.NewCoins(feeCoin)),
		builder.SetGasLimit(1000000000),
	}

	signer := builder.NewKeyringSigner(s.ecfg, s.cctx.Keyring, s.accounts[0], s.cctx.ChainID)
	err := signer.UpdateAccount(s.cctx.GoContext(), s.cctx.GRPCClient)
	require.NoError(t, err)

	msg := createMsgSend(t, signer, s.accounts[1], sdk.NewInt(10000000))

	sdkTx, err := signer.BuildSignedTx(signer.NewTxBuilder(opts...), false, msg)
	require.NoError(t, err)

	rawTx, err := s.ecfg.TxConfig.TxEncoder()(sdkTx)
	require.NoError(t, err)

	resp, err := s.cctx.BroadcastTxSync(rawTx)
	require.NoError(t, err)

	require.Equal(t, abci.CodeTypeOK, resp.Code)

	err = s.cctx.WaitForNextBlock()
	require.NoError(t, err)

	res, err := testfactory.QueryWithoutProof(s.cctx.Context, resp.TxHash)
	require.NoError(t, err)

	require.Equal(t, abci.CodeTypeOK, res.TxResult.Code)
}

func (s *IntegrationTestSuite) TestSecondaryChainIDBuilder() {
	t := s.T()

	// define the tx builder options
	feeCoin := sdk.Coin{
		Denom:  consts.BondDenom,
		Amount: sdk.NewInt(1),
	}

	opts := []builder.TxBuilderOption{
		builder.SetFeeAmount(sdk.NewCoins(feeCoin)),
		builder.SetGasLimit(1000000000),
	}

	secondaryChainID := "taco"
	chainID := strings.Join([]string{s.cctx.ChainID, secondaryChainID}, consts.ChainIDSeparator)

	signer := builder.NewKeyringSigner(s.ecfg, s.cctx.Keyring, s.accounts[0], chainID)
	err := signer.UpdateAccount(s.cctx.GoContext(), s.cctx.GRPCClient)
	require.NoError(t, err)

	addr, err := signer.GetSignerInfo().GetAddress()
	require.NoError(t, err)

	initBal, err := queryBalance(s.cctx, addr)
	require.NoError(t, err)

	amount := sdk.NewInt(1000000000000)

	msg := createMsgSend(t, signer, s.accounts[1], amount)

	sdkTx, err := signer.BuildSignedTx(signer.NewTxBuilder(opts...), true, msg)
	require.NoError(t, err)

	rawTx, err := s.ecfg.TxConfig.TxEncoder()(sdkTx)
	require.NoError(t, err)

	resp, err := s.cctx.BroadcastTxSync(rawTx)
	require.NoError(t, err)

	require.Equal(t, abci.CodeTypeOK, resp.Code)

	err = s.cctx.WaitForNextBlock()
	require.NoError(t, err)

	res, err := testfactory.QueryWithoutProof(s.cctx.Context, resp.TxHash)
	require.NoError(t, err)

	require.Equal(t, abci.CodeTypeOK, res.TxResult.Code)

	currentBal, err := queryBalance(s.cctx, addr)
	require.NoError(t, err)

	// check that the balance only decreased from gas and that the send did not actually get executed
	diff := initBal.Sub(*currentBal)
	require.True(t, diff.Amount.LT(amount))
	require.True(t, diff.Amount.GTE(sdk.NewInt(1)))
}

func createMsgSend(t *testing.T, signer *builder.KeyringSigner, receiver string, amount sdk.Int) *banktypes.MsgSend {
	// create a msg send transaction
	amountCoin := sdk.Coin{
		Denom:  consts.BondDenom,
		Amount: amount,
	}

	addr, err := signer.GetSignerInfo().GetAddress()
	if err != nil {
		panic(err)
	}

	sendAcc, err := signer.Key(receiver)
	require.NoError(t, err)

	sendAddr, err := sendAcc.GetAddress()
	require.NoError(t, err)

	return banktypes.NewMsgSend(addr, sendAddr, sdk.NewCoins(amountCoin))
}

func queryBalance(cctx testnode.Context, addr sdk.AccAddress) (*sdk.Coin, error) {
	qc := banktypes.NewQueryClient(cctx.GRPCClient)

	res, err := qc.Balance(cctx.GoContext(), banktypes.NewQueryBalanceRequest(addr, consts.BondDenom))
	if err != nil {
		return nil, err
	}

	return res.Balance, nil
}
