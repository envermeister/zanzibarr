//! RAR5 şifreleme primitifleri: özel KDF ve AES-256-CBC yardımcıları.
//!
//! RAR5, paroladan anahtar türetmek için standart PBKDF2'nin değiştirilmiş bir
//! sürümünü kullanır (unrar `crypt5.cpp` ile çapraz doğrulandı): tek bir
//! birikim (`Fn`) üç çıktı üretir — AES anahtarı, hash anahtarı ve parola
//! doğrulama değeri. Doğrulama değeri 8 bayta katlanarak başlıktaki
//! PswCheck alanıyla karşılaştırılır; eşleşme, parolanın doğru olduğunun
//! kesin kanıtıdır.

use aes::Aes256;
use cbc::cipher::{BlockDecryptMut, KeyIvInit};
use hmac::{Hmac, Mac};
use sha2::Sha256;
use zeroize::Zeroizing;

type HmacSha256 = Hmac<Sha256>;
type Aes256CbcDec = cbc::Decryptor<Aes256>;

/// AES/CBC blok boyutu; şifreli başlıklar ve dosya verisi bu hizadadır.
pub(crate) const AES_BLOCK_SIZE: u64 = 16;
/// RAR5 tuz ve başlatma vektörü uzunlukları.
pub(crate) const SALT_SIZE: usize = 16;
pub(crate) const INITV_SIZE: usize = 16;
pub(crate) const PSW_CHECK_SIZE: usize = 8;
/// Kabul edilen en büyük KDF tur sayısının log2'si (unrar sınırıyla aynı).
pub(crate) const MAX_KDF_LG2_COUNT: u8 = 24;

/// KDF çıktıları: dosya/başlık anahtarı, hash anahtarı (şimdilik
/// kullanılmıyor) ve parola doğrulama değeri.
pub(crate) struct Kdf5Output {
    pub key: Zeroizing<[u8; 32]>,
    #[allow(dead_code)]
    pub hash_key: Zeroizing<[u8; 32]>,
    pub psw_check_value: Zeroizing<[u8; 32]>,
}

/// RAR5'in özel KDF'si (standart PBKDF2 DEĞİL): `Count = 1 << lg2_count`.
///
/// `u = HMAC(pw, salt || 00 00 00 01)` ile başlar; birikim `fn = u` zinciri
/// boyunca sıfırlanmaz. `Count-1` tur sonunda birikim AES anahtarı, devam
/// eden 16 tur hash anahtarı, son 16 tur parola doğrulama değeri olur.
/// `salt`, arşivde okunduğu uzunluğuyla verilir (RAR5'te her zaman 16 bayt).
pub(crate) fn kdf5(password: &[u8], salt: &[u8], lg2_count: u8) -> Option<Kdf5Output> {
    if lg2_count > MAX_KDF_LG2_COUNT {
        return None;
    }
    let count = 1u64 << lg2_count;

    let mut salt_block = Zeroizing::new(salt.to_vec());
    salt_block.extend_from_slice(&[0, 0, 0, 1]); // blok indeksi: her zaman 1

    let mut u = hmac_sha256(password, &salt_block);
    let mut function = u;
    let mut outputs = Vec::with_capacity(3);
    for rounds in [count - 1, 16, 16] {
        for _ in 0..rounds {
            u = hmac_sha256(password, &u);
            for (acc, byte) in function.iter_mut().zip(u.iter()) {
                *acc ^= byte;
            }
        }
        outputs.push(function);
    }

    Some(Kdf5Output {
        key: Zeroizing::new(outputs[0]),
        hash_key: Zeroizing::new(outputs[1]),
        psw_check_value: Zeroizing::new(outputs[2]),
    })
}

/// 32 baytlık doğrulama değerini 8 baytlık PswCheck'e katlar:
/// `check[i % 8] ^= value[i]`.
pub(crate) fn psw_check_fold(value: &[u8; 32]) -> [u8; PSW_CHECK_SIZE] {
    let mut check = [0u8; PSW_CHECK_SIZE];
    for (index, byte) in value.iter().enumerate() {
        check[index % PSW_CHECK_SIZE] ^= byte;
    }
    check
}

fn hmac_sha256(key: &[u8], data: &[u8]) -> [u8; 32] {
    let mut mac = <HmacSha256 as Mac>::new_from_slice(key).expect("HMAC her anahtarı kabul eder");
    mac.update(data);
    mac.finalize().into_bytes().into()
}

/// Yerinde AES-256-CBC çözümü; `buffer` 16'nın katı olmalı.
pub(crate) fn decrypt_cbc(key: &[u8; 32], iv: &[u8; INITV_SIZE], buffer: &mut [u8]) -> bool {
    if !buffer.len().is_multiple_of(AES_BLOCK_SIZE as usize) {
        return false;
    }
    let Ok(decryptor) = Aes256CbcDec::new_from_slices(key, iv) else {
        return false;
    };
    decryptor
        .decrypt_padded_mut::<cbc::cipher::block_padding::NoPadding>(buffer)
        .is_ok()
}

/// `value`, 16'nın katına yukarı yuvarlanır (şifreli alan uzunlukları).
pub(crate) fn round_up_block(value: u64) -> Option<u64> {
    value
        .checked_add(AES_BLOCK_SIZE - 1)
        .map(|v| v / AES_BLOCK_SIZE * AES_BLOCK_SIZE)
}

#[cfg(test)]
mod tests {
    use super::*;
    use cbc::cipher::BlockEncryptMut;

    type Aes256CbcEnc = cbc::Encryptor<Aes256>;

    fn hex(bytes: &[u8]) -> String {
        bytes.iter().map(|b| format!("{b:02x}")).collect()
    }

    #[test]
    fn kdf_unrar_vektorleri() {
        // unrar crypt5.cpp'nin kendi doğrulama vektörleri; tuz 4 baytlık
        // doğal uzunluğuyla verilir (KDF tuzu okunduğu gibi kullanır).
        let out = kdf5(b"password", b"salt", 0).unwrap();
        assert_eq!(
            hex(&out.key[..]),
            "120fb6cffcf8b32c43e7225256c4f837a86548c92ccc35480805987cb70be17b"
        );
        let out = kdf5(b"password", b"salt", 12).unwrap();
        assert_eq!(
            hex(&out.key[..]),
            "c5e478d59288c841aa530db6845c4c8d962893a001ce4e11a4963873aa98134a"
        );
    }

    #[test]
    fn kdf_ciktilari_birbirinden_ve_paroladan_farklidir() {
        let salt = [7u8; 16];
        let out = kdf5(b"dogru-parola", &salt, 4).unwrap();
        assert_ne!(*out.key, *out.hash_key);
        assert_ne!(*out.key, *out.psw_check_value);
        let other = kdf5(b"yanlis-parola", &salt, 4).unwrap();
        assert_ne!(*out.key, *other.key);
    }

    #[test]
    fn kdf_tur_siniri_asilinca_reddedilir() {
        // MAX_KDF_LG2_COUNT + 1 erken ret döner; sınırın kendisini koşturmak
        // (2^24 HMAC) birim testi dakikalarca sürer, bu yüzden yalnız ret kolu
        // ve sınır değerinin kendisi doğrulanır.
        let salt = [0u8; 16];
        assert!(kdf5(b"x", &salt, MAX_KDF_LG2_COUNT + 1).is_none());
        assert!(kdf5(b"x", &salt, MAX_KDF_LG2_COUNT + 30).is_none());
        assert_eq!(MAX_KDF_LG2_COUNT, 24); // unrar CRYPT5_KDF_LG2_COUNT_MAX
    }

    #[test]
    fn psw_check_katlamasi() {
        let mut value = [0u8; 32];
        for (index, byte) in value.iter_mut().enumerate() {
            *byte = index as u8;
        }
        let check = psw_check_fold(&value);
        // Elle: check[i] = value[i] ^ value[i+8] ^ value[i+16] ^ value[i+24].
        for (i, byte) in check.iter().enumerate() {
            assert_eq!(
                *byte,
                (i as u8) ^ (i as u8 + 8) ^ (i as u8 + 16) ^ (i as u8 + 24)
            );
        }
    }

    #[test]
    fn cbc_cozme_sifrelemenin_tersidir() {
        let key = [0x2au8; 32];
        let iv = [0x0bu8; 16];
        let plain = [0x41u8; 48];
        let mut buf = plain;
        let enc = Aes256CbcEnc::new_from_slices(&key, &iv)
            .unwrap()
            .encrypt_padded_mut::<cbc::cipher::block_padding::NoPadding>(&mut buf, 48)
            .unwrap()
            .to_vec();
        assert_ne!(enc, plain);
        let mut cipher = enc;
        assert!(decrypt_cbc(&key, &iv, &mut cipher));
        assert_eq!(cipher, plain);
        // 16 hizasız tampon reddedilir.
        assert!(!decrypt_cbc(&key, &iv, &mut [0u8; 17]));
    }

    #[test]
    fn round_up_block_hizalama() {
        assert_eq!(round_up_block(0), Some(0));
        assert_eq!(round_up_block(1), Some(16));
        assert_eq!(round_up_block(16), Some(16));
        assert_eq!(round_up_block(17), Some(32));
        assert_eq!(round_up_block(u64::MAX), None);
    }
}
