MODULE = OpenXPKI		PACKAGE = OpenXPKI::Crypto::Backend::OpenSSL::PKCS10

OpenXPKI_Crypto_Backend_OpenSSL_PKCS10
_new_from_der(sv)
	SV * sv
    PREINIT:
	const unsigned char * dercsr;
	STRLEN csrlen;
    CODE:
	dercsr = (unsigned char*) SvPV(sv, csrlen);
	RETVAL = d2i_X509_REQ(NULL,&dercsr,csrlen);
    OUTPUT:
	RETVAL

OpenXPKI_Crypto_Backend_OpenSSL_PKCS10
_new_from_pem(sv)
	SV * sv
    PREINIT:
	unsigned char * pemcsr;
	const unsigned char * dercsr;
	STRLEN csrlen, inlen;
	char inbuf[512];
	BIO *bio_in, *bio_out, *b64;
    CODE:
	pemcsr  = (unsigned char*) SvPV(sv, csrlen);
	bio_in  = BIO_new(BIO_s_mem());
	bio_out = BIO_new(BIO_s_mem());
	b64     = BIO_new(BIO_f_base64());

	/* load encoded data into bio_in */
	BIO_write(bio_in, pemcsr+36, csrlen-36-34);

	/* set EOF for memory bio */
	BIO_set_mem_eof_return(bio_in, 0);

	/* decode data from one bio into another one */
	BIO_push(b64, bio_in);
        while((inlen = BIO_read(b64, inbuf, 512)) > 0)
		BIO_write(bio_out, inbuf, inlen);

	/* create dercsr */
	csrlen = BIO_get_mem_data(bio_out, &dercsr);

	/* create csr */
	RETVAL = d2i_X509_REQ(NULL,&dercsr,csrlen);
	BIO_free(bio_in);
	BIO_free(bio_out);
	BIO_free(b64);
    OUTPUT:
	RETVAL

SV *
version(csr)
	OpenXPKI_Crypto_Backend_OpenSSL_PKCS10 csr
    PREINIT:
	BIO *out;
	char *version;
        long l, i;
        long v;
	const char *neg;
    CODE:
	out = BIO_new(BIO_s_mem());
#if OPENSSL_VERSION_NUMBER < 0x10100000L
	neg=(csr->req_info->version->type == V_ASN1_NEG_INTEGER)?"-":"";
	l=0;
	for (i=0; i<csr->req_info->version->length; i++)
		{ l<<=8; l+=csr->req_info->version->data[i]; }
	/* why we use l and not l+1 like for all other versions? */
	BIO_printf(out,"%s%lu (%s0x%lx)",neg,l,neg,l);
	l = BIO_get_mem_data(out, &version);
#else
        v = X509_REQ_get_version(csr);
	BIO_printf(out,"%l (0x%lx)",l,l);
	l = BIO_get_mem_data(out, &version);
#endif
	RETVAL = newSVpvn(version, l);
	BIO_free(out);
    OUTPUT:
	RETVAL

void
free(csr)
	OpenXPKI_Crypto_Backend_OpenSSL_PKCS10 csr
    CODE:
	if (csr != NULL) X509_REQ_free(csr);

SV *
subject(csr)
	OpenXPKI_Crypto_Backend_OpenSSL_PKCS10 csr
    PREINIT:
	BIO *out;
	char *subject;
	int n;
    CODE:
	out = BIO_new(BIO_s_mem());
#if OPENSSL_VERSION_NUMBER < 0x10100000L
	X509_NAME_print_ex(out, csr->req_info->subject, 0, OPENXPKI_FLAG_RFC2253);
#else
	X509_NAME_print_ex(out, X509_REQ_get_subject_name(csr), 0, OPENXPKI_FLAG_RFC2253);
#endif
	n = BIO_get_mem_data(out, &subject);
	RETVAL = newSVpvn(subject, n);
	BIO_free(out);
    OUTPUT:
	RETVAL

unsigned long
subject_hash(csr)
	OpenXPKI_Crypto_Backend_OpenSSL_PKCS10 csr
    PREINIT:
    CODE:
#if OPENSSL_VERSION_NUMBER < 0x10100000L
	RETVAL = X509_NAME_hash(csr->req_info->subject);
#else
	RETVAL = X509_NAME_hash(X509_REQ_get_subject_name(csr));
#endif
    OUTPUT:
	RETVAL

SV *
fingerprint (csr, digest_name="sha1")
	OpenXPKI_Crypto_Backend_OpenSSL_PKCS10 csr
	char *digest_name
    PREINIT:
	BIO *out;
	int j;
	unsigned int n;
	const EVP_MD *digest;
	char * fingerprint;
	unsigned char md[EVP_MAX_MD_SIZE];
    CODE:
	out = BIO_new(BIO_s_mem());
	if (!strcmp ("sha1", digest_name))
		digest = EVP_sha1();
	else
		digest = EVP_md5();
	if (X509_REQ_digest(csr,digest,md,&n))
	{
		BIO_printf(out, "%s:", OBJ_nid2sn(EVP_MD_type(digest)));
		for (j=0; j<(int)n; j++)
		{
			BIO_printf (out, "%02X",md[j]);
			if (j+1 != (int)n) BIO_printf(out,":");
		}
	}
	n = BIO_get_mem_data(out, &fingerprint);
	RETVAL = newSVpvn(fingerprint, n);
	BIO_free(out);
    OUTPUT:
	RETVAL

SV *
emailaddress (csr)
	OpenXPKI_Crypto_Backend_OpenSSL_PKCS10 csr
    PREINIT:
	int j, n;
#if (OPENSSL_VERSION_NUMBER < 0x1000000fL)
        STACK *emlst;
#else
        STACK_OF(OPENSSL_STRING) *emlst;
#endif
	BIO *out;
	char *emails;
    CODE:
	out = BIO_new(BIO_s_mem());
	emlst = X509_REQ_get1_email(csr);
	if (emlst != NULL)
	{
#if (OPENSSL_VERSION_NUMBER < 0x1000000fL)
		for (j = 0; j < sk_num(emlst); j++)
		{
			BIO_printf(out, "%s", sk_value(emlst, j));
			if (j+1 != (int)sk_num(emlst))
#else
		for (j = 0; j < sk_OPENSSL_STRING_num(emlst); j++)
		{
			BIO_printf(out, "%s", sk_OPENSSL_STRING_value(emlst, j));
			if (j+1 != (int)sk_OPENSSL_STRING_num(emlst))
#endif
				BIO_printf(out,"\n");
		}
		X509_email_free(emlst);
	}
	n = BIO_get_mem_data(out, &emails);
	RETVAL = newSVpvn(emails, n);
	BIO_free(out);
    OUTPUT:
	RETVAL

SV *
pubkey_algorithm(csr)
	OpenXPKI_Crypto_Backend_OpenSSL_PKCS10 csr
    PREINIT:
	BIO *out;
	char *alg;
	X509_REQ_INFO *ri;
	X509_PUBKEY *xpkey;
        ASN1_OBJECT *xpoid;
	int n;
    CODE:
	out = BIO_new(BIO_s_mem());
#if OPENSSL_VERSION_NUMBER < 0x10100000L
	ri = csr->req_info;
	i2a_ASN1_OBJECT(out, ri->pubkey->algor->algorithm);
#else
	xpkey = X509_REQ_get_X509_PUBKEY(csr);
        X509_PUBKEY_get0_param(&xpoid, NULL, NULL, NULL, xpkey);
	i2a_ASN1_OBJECT(out, xpoid);
#endif
	n = BIO_get_mem_data(out, &alg);
	RETVAL = newSVpvn(alg, n);
	BIO_free(out);
    OUTPUT:
	RETVAL

SV *
pubkey(csr)
	OpenXPKI_Crypto_Backend_OpenSSL_PKCS10 csr
    PREINIT:
	BIO *out;
	EVP_PKEY *pkey;
        RSA *rsa = NULL;
        DSA *dsa = NULL;
	EC_KEY *ec = NULL;
	char *pubkey;
	int n;
    CODE:
	out = BIO_new(BIO_s_mem());
	pkey=X509_REQ_get_pubkey(csr);
	if (pkey != NULL)
	{
#if OPENSSL_VERSION_NUMBER < 0x10100000L
		if (pkey->type == EVP_PKEY_RSA)
			RSA_print(out,pkey->pkey.rsa,0);
		else if (pkey->type == EVP_PKEY_DSA)
			DSA_print(out,pkey->pkey.dsa,0);
                else if (pkey->type == EVP_PKEY_EC)
                        EC_KEY_print(out,pkey->pkey.ec,0);
#else
		if (EVP_PKEY_id(pkey) == EVP_PKEY_RSA) {
		  rsa = EVP_PKEY_get1_RSA(pkey);
		  RSA_print(out,rsa,0);
		}
		else if (EVP_PKEY_id(pkey) == EVP_PKEY_DSA) {
		  dsa = EVP_PKEY_get1_DSA(pkey);
		  DSA_print(out,dsa,0);
		}
                else if (EVP_PKEY_id(pkey) == EVP_PKEY_EC) {
		  ec = EVP_PKEY_get1_EC_KEY(pkey);
		  EC_KEY_print(out,ec,0);
		}
#endif		
		EVP_PKEY_free(pkey);
	}
	n = BIO_get_mem_data(out, &pubkey);
	RETVAL = newSVpvn(pubkey, n);
	BIO_free(out);
    OUTPUT:
	RETVAL

SV *
pubkey_hash (csr, digest_name="sha1")
	OpenXPKI_Crypto_Backend_OpenSSL_PKCS10 csr
	char *digest_name
    PREINIT:
	EVP_PKEY *pkey;
	BIO *out;
	int j;
	unsigned int n;
	const EVP_MD *digest;
	char * fingerprint;
	unsigned char md[EVP_MAX_MD_SIZE];
	unsigned char *data = NULL;
	int length;
    CODE:
	out = BIO_new(BIO_s_mem());
	pkey=X509_REQ_get_pubkey(csr);
	if (pkey != NULL)
	{
		length = i2d_PublicKey (pkey, NULL);
		/* data = OPENSSL_malloc(length+1); */
	        /* Do not free this pointer! It is from the EVP_PKEY structure. */
		length = i2d_PublicKey (pkey, &data);
		if (!strcmp ("sha1", digest_name))
			digest = EVP_sha1();
		else
			digest = EVP_md5();

		if (EVP_Digest(data, length, md, &n, digest, NULL))
		{
			BIO_printf(out, "%s:", OBJ_nid2sn(EVP_MD_type(digest)));
			for (j=0; j<(int)n; j++)
			{
				BIO_printf (out, "%02X",md[j]);
				if (j+1 != (int)n) BIO_printf(out,":");
			}
		}
		/* OPENSSL_free (data); */
		EVP_PKEY_free(pkey);
	}
	n = BIO_get_mem_data(out, &fingerprint);
	RETVAL = newSVpvn(fingerprint, n);
	BIO_free(out);
    OUTPUT:
	RETVAL

SV *
keysize (csr)
	OpenXPKI_Crypto_Backend_OpenSSL_PKCS10 csr
    PREINIT:
	BIO *out;
	EVP_PKEY *pkey;
	char * length;
	int n;
    CODE:
	out = BIO_new(BIO_s_mem());
	pkey=X509_REQ_get_pubkey(csr);
	if (pkey != NULL)
	{
            BIO_printf(out,"%d", EVP_PKEY_bits(pkey));
	}
	n = BIO_get_mem_data(out, &length);
	RETVAL = newSVpvn(length, n);
	BIO_free(out);
    OUTPUT:
	RETVAL

SV *
modulus (csr)
	OpenXPKI_Crypto_Backend_OpenSSL_PKCS10 csr
    PREINIT:
	char * modulus;
	BIO *out;
	EVP_PKEY *pkey;
        RSA *rsa = NULL;
        DSA *dsa = NULL;
	const BIGNUM *n_bignum;
	int n;
    CODE:
	out = BIO_new(BIO_s_mem());
	pkey=X509_REQ_get_pubkey(csr);
	if (pkey != NULL)
	{
#if OPENSSL_VERSION_NUMBER < 0x10100000L
	    if (pkey->type == EVP_PKEY_RSA)
		BN_print(out,pkey->pkey.rsa->n);
            if (pkey->type == EVP_PKEY_DSA)
		BN_print(out,pkey->pkey.dsa->pub_key);
#else
	    if (EVP_PKEY_id(pkey) == EVP_PKEY_RSA) {
	        rsa = EVP_PKEY_get1_RSA(pkey);
		RSA_get0_key(rsa, &n_bignum, NULL, NULL);
		BN_print(out,n_bignum);
	    }
            if (EVP_PKEY_id(pkey) == EVP_PKEY_DSA) {
	        dsa = EVP_PKEY_get1_DSA(pkey);
	        DSA_get0_key(dsa, &n_bignum, NULL);
		BN_print(out,n_bignum);
	    }
#endif	    
	    EVP_PKEY_free(pkey);
	}
	n = BIO_get_mem_data(out, &modulus);
	RETVAL = newSVpvn(modulus, n);
	BIO_free(out);
    OUTPUT:
	RETVAL

SV *
exponent (csr)
	OpenXPKI_Crypto_Backend_OpenSSL_PKCS10 csr
    PREINIT:
	BIO *out;
	EVP_PKEY *pkey;
        RSA *rsa = NULL;
        DSA *dsa = NULL;
        const BIGNUM *e_bignum;
	char *exponent;
	int n;
    CODE:
	out = BIO_new(BIO_s_mem());
	pkey=X509_REQ_get_pubkey(csr);
	if (pkey != NULL)
	{
#if OPENSSL_VERSION_NUMBER < 0x10100000L
	    if (pkey->type == EVP_PKEY_RSA)
		BN_print(out,pkey->pkey.rsa->e);
	    if (pkey->type == EVP_PKEY_DSA)
		BN_print(out,pkey->pkey.dsa->pub_key);
#else
	    if (EVP_PKEY_id(pkey) == EVP_PKEY_RSA) {
                rsa = EVP_PKEY_get1_RSA(pkey);
		RSA_get0_key(rsa, NULL, &e_bignum, NULL);
		BN_print(out,e_bignum);
	    }
	    if (EVP_PKEY_id(pkey) == EVP_PKEY_DSA) {
	        dsa = EVP_PKEY_get1_DSA(pkey);
	        DSA_get0_key(dsa, &e_bignum, NULL);
		BN_print(out,e_bignum);
	    }
#endif	    
	    EVP_PKEY_free(pkey);
	}
	n = BIO_get_mem_data(out, &exponent);
	RETVAL = newSVpvn(exponent, n);
	BIO_free(out);
    OUTPUT:
	RETVAL

SV *
extensions(csr)
	OpenXPKI_Crypto_Backend_OpenSSL_PKCS10 csr
    PREINIT:
	BIO *out;
	char *ext;
	int n;
    CODE:
	out = BIO_new(BIO_s_mem());
	// there is a bug in X509V3_extensions_print
	// the causes the function to fail if title == NULL and indent == 0
	X509V3_extensions_print(out, NULL, X509_REQ_get_extensions(csr), 0, 4);
	n = BIO_get_mem_data(out, &ext);
	RETVAL = newSVpvn(ext, n);
	BIO_free(out);
    OUTPUT:
	RETVAL

SV *
attributes(csr)
	OpenXPKI_Crypto_Backend_OpenSSL_PKCS10 csr
    PREINIT:
	BIO *out;
	char *attr;
	STACK_OF(X509_ATTRIBUTE) *sk;
	int n,i;
    CODE:
	out = BIO_new(BIO_s_mem());
#if OPENSSL_VERSION_NUMBER < 0x10100000L
	sk=csr->req_info->attributes;
	for (i=0; i<sk_X509_ATTRIBUTE_num(sk); i++)
#else
	for (i=0; i<X509_REQ_get_attr_count(csr); i++)
#endif
	{
		ASN1_TYPE *at;
		X509_ATTRIBUTE *a;
		ASN1_BIT_STRING *bs=NULL;
		ASN1_TYPE *t;
		ASN1_OBJECT *aobj;
		int j,type=0,count=1,ii=0;
#if OPENSSL_VERSION_NUMBER < 0x10100000L
		a=sk_X509_ATTRIBUTE_value(sk,i);
		if(X509_REQ_extension_nid(OBJ_obj2nid(a->object)))
			continue;
		if ((j=i2a_ASN1_OBJECT(out,a->object)) > 0)
		{
			if (a->single)
			{
				t=a->value.single;
				type=t->type;
				bs=t->value.bit_string;
			}
			else
			{
				ii=0;
				count=sk_ASN1_TYPE_num(a->value.set);
get_next:
				at=sk_ASN1_TYPE_value(a->value.set,ii);
				type=at->type;
				bs=at->value.asn1_string;
			}
		}
#else
		a = X509_REQ_get_attr(csr, i);
		aobj = X509_ATTRIBUTE_get0_object(a);
		if(X509_REQ_extension_nid(OBJ_obj2nid(aobj)))
			continue;
		if ((j=i2a_ASN1_OBJECT(out,aobj)) > 0)
		{
		  ii = 0;
		  count = X509_ATTRIBUTE_count(a);
get_next:
		  at = X509_ATTRIBUTE_get0_type(a, ii);
                  type = at->type;
                  bs = at->value.asn1_string;
		}
#endif
		for (j=25-j; j>0; j--)
			BIO_write(out," ",1);
		BIO_puts(out,":");
		if (    (type == V_ASN1_PRINTABLESTRING) ||
			(type == V_ASN1_T61STRING) ||
			(type == V_ASN1_UTF8STRING) ||
			(type == V_ASN1_IA5STRING))
		{
			BIO_write(out,(char *)bs->data,bs->length);
			BIO_puts(out,"\n");
		}
		else
			BIO_puts(out,"unable to print attribute\n");
		if (++ii < count) goto get_next;
	}
	n = BIO_get_mem_data(out, &attr);
	RETVAL = newSVpvn(attr, n);
	BIO_free(out);
    OUTPUT:
	RETVAL

SV *
signature_algorithm(csr)
	OpenXPKI_Crypto_Backend_OpenSSL_PKCS10 csr
    PREINIT:
	BIO *out;
	char *sig;
	const X509_ALGOR *sig_alg;
	const ASN1_BIT_STRING *signature;
	int n;
    CODE:
	out = BIO_new(BIO_s_mem());
#if OPENSSL_VERSION_NUMBER < 0x10100000L
	i2a_ASN1_OBJECT(out, csr->sig_alg->algorithm);
#else
	X509_REQ_get0_signature(csr, &signature, &sig_alg);
	i2a_ASN1_OBJECT(out, sig_alg->algorithm);
#endif
	n = BIO_get_mem_data(out, &sig);
	RETVAL = newSVpvn(sig, n);
	BIO_free(out);
    OUTPUT:
	RETVAL

SV *
signature(csr)
	OpenXPKI_Crypto_Backend_OpenSSL_PKCS10 csr
    PREINIT:
	BIO *out;
	char *sig;
	const ASN1_BIT_STRING *signature;
	const X509_ALGOR *sig_alg;
	int n,i;
	unsigned char *s;
    CODE:
	out = BIO_new(BIO_s_mem());
#if OPENSSL_VERSION_NUMBER < 0x10100000L
	n=csr->signature->length;
	s=csr->signature->data;
#else
        X509_REQ_get0_signature(csr, &signature, &sig_alg);
	n=signature->length;
	s=signature->data;
#endif	
	for (i=0; i<n; i++)
	{
		if ( ((i%18) == 0) && (i!=0) ) BIO_printf(out,"\n");
		BIO_printf(out,"%02x%s",s[i], (((i+1)%18) == 0)?"":":");
	}
	n = BIO_get_mem_data(out, &sig);
	RETVAL = newSVpvn(sig, n);
	BIO_free(out);
    OUTPUT:
	RETVAL
