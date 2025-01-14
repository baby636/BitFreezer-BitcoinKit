#import "CryptoKitPrivate.h"
#import <openssl/sha.h>
#import <openssl/ripemd.h>
#import <openssl/hmac.h>
#import <openssl/ec.h>
#import <openssl/ecdh.h>
#import <openssl/aes.h>
#import <scrypt/scrypt.h>



@implementation _Hash

+ (NSData *)sha256:(NSData *)data {
    NSMutableData *result = [NSMutableData dataWithLength:SHA256_DIGEST_LENGTH];
    SHA256(data.bytes, data.length, result.mutableBytes);
    return result;
}

+ (NSData *)concatKDF:(NSData *)data {
    NSMutableData *result = [NSMutableData dataWithLength:SHA256_DIGEST_LENGTH];
    unsigned char tmp[] = {0, 0, 0, 1};

    SHA256_CTX sha256;
    SHA256_Init(&sha256);
    SHA256_Update(&sha256, tmp, 4);
    SHA256_Update(&sha256, data.bytes, 32);
    SHA256_Final(result.mutableBytes, &sha256);

    return result;
}

+ (NSData *)sha256sha256:(NSData *)data {
    return [self sha256:[self sha256:data]];
}

+ (NSData *)ripemd160:(NSData *)data {
    NSMutableData *result = [NSMutableData dataWithLength:RIPEMD160_DIGEST_LENGTH];
    RIPEMD160(data.bytes, data.length, result.mutableBytes);
    return result;
}

+ (NSData *)sha256ripemd160:(NSData *)data {
    return [self ripemd160:[self sha256:data]];
}

+ (NSData *)hmacsha512:(NSData *)data key:(NSData *)key {
    unsigned int length = SHA512_DIGEST_LENGTH;
    NSMutableData *result = [NSMutableData dataWithLength:length];
    HMAC(EVP_sha512(), key.bytes, (int)key.length, data.bytes, data.length, result.mutableBytes, &length);
    return result;
}

+ (NSData *)hmacsha256:(NSData *)data key:(NSData *)key iv:(NSData *)iv macData:(NSData *)macData {
    HMAC_CTX ctx;
    HMAC_CTX_init(&ctx);
    HMAC_Init(&ctx, key.bytes, (int) key.length, EVP_sha256());

    HMAC_Update(&ctx, iv.bytes, (int) iv.length);
    HMAC_Update(&ctx, data.bytes, (int) data.length);
    HMAC_Update(&ctx, macData.bytes, (int) macData.length);

    unsigned int length = SHA256_DIGEST_LENGTH;
    NSMutableData *result = [NSMutableData dataWithLength:length];
    HMAC_Final(&ctx, result.mutableBytes, &length);

    HMAC_CTX_cleanup(&ctx);

    return result;
}

+ (UInt8 *)scrypt: (UInt8 *)pass passLength:(UInt32)passLength salt:(UInt8 *)salt saltLength:(UInt32) saltLength n:(UInt64)n r:(UInt32)r p:(UInt32)p outLength:(UInt32) outLength {

    UInt8 *result = (UInt8 *)calloc(outLength, sizeof(UInt8));
    scrypt(pass, passLength, salt, saltLength, n, r, p, result, outLength);

    return result;
}

@end

@implementation _ECKey

- (instancetype)privateKey:(NSData *)privateKey publicKey:(NSData *)publicKey {
    _privateKey = privateKey;
    _publicKey = publicKey;
    return self;
}

+ (_ECKey *)random {
    BN_CTX *ctx = BN_CTX_new();
    EC_KEY *key = EC_KEY_new_by_curve_name(NID_secp256k1);
    EC_KEY_generate_key(key);
    const EC_GROUP *group = EC_KEY_get0_group(key);

    // private key
    const BIGNUM *prv = EC_KEY_get0_private_key(key);
    NSMutableData *prvBytes = [NSMutableData dataWithLength:32];
    BN_bn2bin(prv, prvBytes.mutableBytes);

    // public key
    const EC_POINT *pubPoint = EC_KEY_get0_public_key(key);
    NSMutableData *pubBytes = [NSMutableData dataWithLength:65];
    BIGNUM *pub = BN_new();
    EC_POINT_point2bn(group, pubPoint, POINT_CONVERSION_UNCOMPRESSED, pub, ctx);
    BN_bn2bin(pub, pubBytes.mutableBytes);

    BN_CTX_free(ctx);
    EC_KEY_free(key);
    BN_free(pub);

    return [[_ECKey alloc] privateKey:prvBytes publicKey:pubBytes];
}

@end

@implementation _AES

+ (NSData *)encrypt:(NSData *)data withKey:(NSData *)key keySize:(NSInteger)keySize iv:(NSData *)iv {
    NSMutableData *result = [NSMutableData dataWithLength:data.length];

    AES_KEY aesKey;
    AES_set_encrypt_key(key.bytes, (int) keySize, &aesKey);
    unsigned char ecountBuf[16] = {0};
    unsigned int num = 0;

    AES_ctr128_encrypt(data.bytes, result.mutableBytes, (size_t) data.length, &aesKey, (unsigned char*) iv.bytes, ecountBuf, &num);

    return result;
}

+ (NSData *)encrypt:(NSData *)data withKey:(NSData *)key keySize:(NSInteger)keySize {
    NSMutableData *result = [NSMutableData dataWithLength:data.length];

    AES_KEY aesKey;
    AES_set_encrypt_key(key.bytes, (int) keySize, &aesKey);

    AES_encrypt(data.bytes, result.mutableBytes, &aesKey);

    return result;
}

@end

@implementation _ECDH

+ (unsigned char *)agree:(NSData *)privateKey withPublicKey:(NSData *)publicKey {
    BN_CTX *ctx = BN_CTX_new();
    EC_KEY *key = EC_KEY_new_by_curve_name(NID_secp256k1);
    BIGNUM *prv = BN_new();
    BIGNUM *pub = BN_new();
    const EC_GROUP *group = EC_KEY_get0_group(key);
    EC_POINT *pubPoint = EC_POINT_new(group);
    int secretLen = 32;

    BN_bin2bn(privateKey.bytes, (int) privateKey.length, prv);
    BN_bin2bn(publicKey.bytes, (int) publicKey.length, pub);

    EC_KEY_set_private_key(key, prv);
    EC_POINT_bn2point(group, pub, pubPoint, ctx);

    unsigned char *secret = (unsigned char *) malloc(secretLen);

    ECDH_compute_key(secret, secretLen, pubPoint, key, NULL);

    BN_CTX_free(ctx);
    EC_KEY_free(key);
    BN_free(prv);
    BN_free(pub);
    EC_POINT_free(pubPoint);

    return secret;
}

@end

@implementation _Key

+ (NSData *)computePublicKeyFromPrivateKey:(NSData *)privateKey compression:(BOOL)compression {
    BN_CTX *ctx = BN_CTX_new();
    EC_KEY *key = EC_KEY_new_by_curve_name(NID_secp256k1);
    const EC_GROUP *group = EC_KEY_get0_group(key);

    BIGNUM *prv = BN_new();
    BN_bin2bn(privateKey.bytes, (int)privateKey.length, prv);

    EC_POINT *pub = EC_POINT_new(group);
    EC_POINT_mul(group, pub, prv, nil, nil, ctx);
    EC_KEY_set_private_key(key, prv);
    EC_KEY_set_public_key(key, pub);

    NSMutableData *result;
    if (compression) {
        EC_KEY_set_conv_form(key, POINT_CONVERSION_COMPRESSED);
        unsigned char *bytes = NULL;
        int length = i2o_ECPublicKey(key, &bytes);
        result = [NSMutableData dataWithBytesNoCopy:bytes length:length];
    } else {
        result = [NSMutableData dataWithLength:65];
        BIGNUM *n = BN_new();
        EC_POINT_point2bn(group, pub, POINT_CONVERSION_UNCOMPRESSED, n, ctx);
        BN_bn2bin(n, result.mutableBytes);
        BN_free(n);
    }

    EC_POINT_free(pub);
    BN_free(prv);
    EC_KEY_free(key);
    BN_CTX_free(ctx);

    return result;
}

+ (NSData *)deriveKey:(NSData *)password salt:(NSData *)salt iterations:(NSInteger)iterations keyLength:(NSInteger)keyLength {
    NSMutableData *result = [NSMutableData dataWithLength:keyLength];
    PKCS5_PBKDF2_HMAC(password.bytes, (int)password.length, salt.bytes, (int)salt.length, (int)iterations, EVP_sha512(), (int)keyLength, result.mutableBytes);
    return result;
}

@end

@implementation _HDKey

- (instancetype)initWithPrivateKey:(NSData *)privateKey publicKey:(NSData *)publicKey chainCode:(NSData *)chainCode depth:(uint8_t)depth fingerprint:(uint32_t)fingerprint childIndex:(uint32_t)childIndex {
    self = [super init];
    if (self) {
        _privateKey = privateKey;
        _publicKey = publicKey;
        _chainCode = chainCode;
        _depth = depth;
        _fingerprint = fingerprint;
        _childIndex = childIndex;
    }
    return self;
}

- (_HDKey *)derivedAtIndex:(uint32_t)index hardened:(BOOL)hardened {
    BN_CTX *ctx = BN_CTX_new();

    NSMutableData *data = [NSMutableData data];
    if (hardened) {
        uint8_t padding = 0;
        [data appendBytes:&padding length:1];
        [data appendData:self.privateKey];
    } else {
        [data appendData:self.publicKey];
    }

    uint32_t childIndex = OSSwapHostToBigInt32(hardened ? (0x80000000 | index) : index);
    [data appendBytes:&childIndex length:sizeof(childIndex)];

    NSData *digest = [_Hash hmacsha512:data key:self.chainCode];
    NSData *derivedPrivateKey = [digest subdataWithRange:NSMakeRange(0, 32)];
    NSData *derivedChainCode = [digest subdataWithRange:NSMakeRange(32, 32)];

    BIGNUM *curveOrder = BN_new();
    BN_hex2bn(&curveOrder, "FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141");

    BIGNUM *factor = BN_new();
    BN_bin2bn(derivedPrivateKey.bytes, (int)derivedPrivateKey.length, factor);
    // Factor is too big, this derivation is invalid.
    if (BN_cmp(factor, curveOrder) >= 0) {
        return nil;
    }

    NSMutableData *result;
    if (self.privateKey) {
        BIGNUM *privateKey = BN_new();
        BN_bin2bn(self.privateKey.bytes, (int)self.privateKey.length, privateKey);

        BN_mod_add(privateKey, privateKey, factor, curveOrder, ctx);
        // Check for invalid derivation.
        if (BN_is_zero(privateKey)) {
            return nil;
        }

        int numBytes = BN_num_bytes(privateKey);
        result = [NSMutableData dataWithLength:numBytes];
        BN_bn2bin(privateKey, result.mutableBytes);

        BN_free(privateKey);
    } else {
        BIGNUM *publicKey = BN_new();
        BN_bin2bn(self.publicKey.bytes, (int)self.publicKey.length, publicKey);
        EC_GROUP *group = EC_GROUP_new_by_curve_name(NID_secp256k1);

        EC_POINT *point = EC_POINT_new(group);
        EC_POINT_bn2point(group, publicKey, point, ctx);
        EC_POINT_mul(group, point, factor, point, BN_value_one(), ctx);
        // Check for invalid derivation.
        if (EC_POINT_is_at_infinity(group, point) == 1) {
            return nil;
        }

        BIGNUM *n = BN_new();
        result = [NSMutableData dataWithLength:33];

        EC_POINT_point2bn(group, point, POINT_CONVERSION_COMPRESSED, n, ctx);
        BN_bn2bin(n, result.mutableBytes);

        BN_free(n);
        BN_free(publicKey);
        EC_POINT_free(point);
        EC_GROUP_free(group);
    }

    BN_free(factor);
    BN_free(curveOrder);
    BN_CTX_free(ctx);

    uint32_t *fingerPrint = (uint32_t *)[_Hash sha256ripemd160:self.publicKey].bytes;
    return [[_HDKey alloc] initWithPrivateKey:result publicKey:result chainCode:derivedChainCode depth:self.depth + 1 fingerprint:*fingerPrint childIndex:childIndex];
}

@end
