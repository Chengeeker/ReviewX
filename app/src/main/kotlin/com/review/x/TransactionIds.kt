package com.review.x

import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.security.MessageDigest
import java.security.SecureRandom
import java.util.Base64
import org.json.JSONArray

// Port of the existing MIT encoder; see assets/licenses/fa0311-transaction-mit.txt.
class TransactionIds(source: String) {
    private val random = SecureRandom()
    private val pairs = JSONArray(source).objects().map { it.getString("verification") to it.getString("animationKey") }
    init { require(pairs.isNotEmpty()); pairs.forEach { require(Base64.getDecoder().decode(it.first).isNotEmpty() && it.second.isNotEmpty()) } }
    fun create(method: String, path: String): String {
        val pair = pairs[random.nextInt(pairs.size)]
        return encode(method, path, pair.first, pair.second, System.currentTimeMillis() / 1000 - 1682924400, random.nextInt(256))
    }
    companion object {
        fun encode(method: String, path: String, verification: String, animation: String, time: Long, mask: Int): String {
            require(time in 0..0xffffffffL && mask in 0..255)
            val digest = MessageDigest.getInstance("SHA-256").digest("$method!$path!${time}obfiowerehiring$animation".toByteArray(Charsets.UTF_8))
            val payload = Base64.getDecoder().decode(verification) + ByteBuffer.allocate(4).order(ByteOrder.LITTLE_ENDIAN).putInt(time.toInt()).array() + digest.copyOf(16) + byteArrayOf(3)
            return Base64.getEncoder().withoutPadding().encodeToString(byteArrayOf(mask.toByte()) + payload.map { (it.toInt() xor mask).toByte() }.toByteArray())
        }
    }
}
