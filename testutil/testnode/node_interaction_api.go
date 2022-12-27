package testnode

import (
	"context"
	"errors"
	"time"

	"github.com/cosmos/cosmos-sdk/client"
)

type Context struct {
	rootCtx context.Context
	client.Context
}

func (c *Context) GoContext() context.Context {
	return c.rootCtx
}

// LatestHeight returns the latest height of the network or an error if the
// query fails.
func (c *Context) LatestHeight() (int64, error) {
	status, err := c.Client.Status(c.GoContext())
	if err != nil {
		return 0, err
	}

	return status.SyncInfo.LatestBlockHeight, nil
}

// WaitForHeightWithTimeout is the same as WaitForHeight except the caller can
// provide a custom timeout.
func (c *Context) WaitForHeightWithTimeout(h int64, t time.Duration) (int64, error) {
	ticker := time.NewTicker(time.Second)
	defer ticker.Stop()

	ctx, cancel := context.WithTimeout(c.rootCtx, t)
	defer cancel()

	var latestHeight int64
	for {
		select {
		case <-ctx.Done():
			return latestHeight, errors.New("timeout exceeded waiting for block")
		case <-ticker.C:
			latestHeight, err := c.LatestHeight()
			if err != nil {
				return 0, err
			}
			if latestHeight >= h {
				return latestHeight, nil
			}
		}
	}
}

// WaitForHeight performs a blocking check where it waits for a block to be
// committed after a given block. If that height is not reached within a timeout,
// an error is returned. Regardless, the latest height queried is returned.
func (c *Context) WaitForHeight(h int64) (int64, error) {
	return c.WaitForHeightWithTimeout(h, 10*time.Second)
}

// WaitForNextBlock waits for the next block to be committed, returning an error
// upon failure.
func (c *Context) WaitForNextBlock() error {
	lastBlock, err := c.LatestHeight()
	if err != nil {
		return err
	}

	_, err = c.WaitForHeight(lastBlock + 1)
	if err != nil {
		return err
	}

	return err
}
