package blobstore

import (
	"bytes"
	"context"
	"errors"
	"io"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/credentials"
	"github.com/aws/aws-sdk-go-v2/service/s3"
	"github.com/aws/aws-sdk-go-v2/service/s3/types"
)

// B2Store stores encrypted blobs in a Backblaze B2 bucket via B2's
// S3-compatible API. Nothing B2-specific leaks past this file — from the
// rest of the app's perspective it's just another Store implementation.
type B2Store struct {
	client *s3.Client
	bucket string
}

type B2Config struct {
	// Endpoint is the bucket's S3-compatible endpoint shown in the
	// Backblaze console, e.g. "https://s3.us-west-004.backblazeb2.com".
	Endpoint string
	// Region is the region portion of that endpoint, e.g. "us-west-004".
	Region         string
	Bucket         string
	KeyID          string
	ApplicationKey string
}

func NewB2Store(cfg B2Config) *B2Store {
	client := s3.New(s3.Options{
		Region:       cfg.Region,
		BaseEndpoint: aws.String(cfg.Endpoint),
		Credentials:  credentials.NewStaticCredentialsProvider(cfg.KeyID, cfg.ApplicationKey, ""),
		// B2's S3-compatible API expects path-style requests
		// (endpoint/bucket/key), not virtual-hosted-style.
		UsePathStyle: true,
	})
	return &B2Store{client: client, bucket: cfg.Bucket}
}

func (s *B2Store) Put(ctx context.Context, key string, data []byte) error {
	_, err := s.client.PutObject(ctx, &s3.PutObjectInput{
		Bucket: aws.String(s.bucket),
		Key:    aws.String(key),
		Body:   bytes.NewReader(data),
	})
	return err
}

func (s *B2Store) Get(ctx context.Context, key string) ([]byte, error) {
	out, err := s.client.GetObject(ctx, &s3.GetObjectInput{
		Bucket: aws.String(s.bucket),
		Key:    aws.String(key),
	})
	if err != nil {
		var noSuchKey *types.NoSuchKey
		if errors.As(err, &noSuchKey) {
			return nil, ErrNotFound
		}
		return nil, err
	}
	defer out.Body.Close()
	return io.ReadAll(out.Body)
}

func (s *B2Store) Delete(ctx context.Context, key string) error {
	_, err := s.client.DeleteObject(ctx, &s3.DeleteObjectInput{
		Bucket: aws.String(s.bucket),
		Key:    aws.String(key),
	})
	return err
}
