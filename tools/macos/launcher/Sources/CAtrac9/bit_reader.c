#include "bit_reader.h"
#include "utility.h"

static int PeekIntFallback(BitReaderCxt* br, int bitCount);

void InitBitReaderCxt(BitReaderCxt* br, const void * buffer, int bufferSize)
{
	br->Buffer = buffer;
	br->Position = 0;
	br->LengthBits = bufferSize * 8;
}

int ReadInt(BitReaderCxt* br, const int bits)
{
	const int value = PeekInt(br, bits);
	br->Position += bits;
	return value;
}

int ReadSignedInt(BitReaderCxt* br, const int bits)
{
	const int value = PeekInt(br, bits);
	br->Position += bits;
	return SignExtend32(value, bits);
}

int ReadOffsetBinary(BitReaderCxt* br, const int bits)
{
	const int offset = 1 << (bits - 1);
	const int value = PeekInt(br, bits) - offset;
	br->Position += bits;
	return value;
}

int PeekInt(BitReaderCxt* br, const int bits)
{
	if (br->Position >= br->LengthBits)
	{
		return 0;
	}
	const int remaining = br->LengthBits - br->Position;
	if (bits > remaining)
	{
		const int extraBits = bits - remaining;
		return PeekIntFallback(br, remaining) << extraBits;
	}

	const int byteIndex = br->Position >> 3;
	const int bitIndex = br->Position & 7;
	const unsigned char* buffer = br->Buffer;
	if (bits > 0 && bits <= 24 && byteIndex + 4 <= (br->LengthBits >> 3)) {
		const unsigned raw = ((unsigned)buffer[byteIndex] << 24) | ((unsigned)buffer[byteIndex + 1] << 16) | ((unsigned)buffer[byteIndex + 2] << 8) | (unsigned)buffer[byteIndex + 3];
		return (int)((raw << bitIndex) >> (32 - bits));
	}
	const int numBytes = (bitIndex + bits - 1) / 8 + 1;
	int value;
	switch (numBytes) {
	case 1:
		value = buffer[byteIndex];
		value &= 0xFF >> bitIndex;
		value >>= 8 - bits - bitIndex;
		break;
	case 2:
		value = buffer[byteIndex] << 8 | buffer[byteIndex + 1];
		value &= 0xFFFF >> bitIndex;
		value >>= 16 - bits - bitIndex;
		break;
	case 3:
		value = buffer[byteIndex] << 16 | buffer[byteIndex + 1] << 8 | buffer[byteIndex + 2];
		value &= 0xFFFFFF >> bitIndex;
		value >>= 24 - bits - bitIndex;
		break;
	case 4:
		value = buffer[byteIndex] << 24
			| buffer[byteIndex + 1] << 16
			| buffer[byteIndex + 2] << 8
			| buffer[byteIndex + 3];
		value &= (int)(0xFFFFFFFF >> bitIndex);
		value >>= 32 - bits - bitIndex;
		break;
	default:
		value = PeekIntFallback(br, bits);
		break;
	}
	return value;
}

void AlignPosition(BitReaderCxt* br, const unsigned int multiple)
{
	const int position = br->Position;
	if (position % multiple == 0)
	{
		return;
	}

	br->Position = position + multiple - position % multiple;
}

static int PeekIntFallback(BitReaderCxt* br, int bitCount)
{
	int value = 0;
	int byteIndex = br->Position / 8;
	int bitIndex = br->Position % 8;
	const unsigned char* buffer = br->Buffer;

	while (bitCount > 0)
	{
		if (bitIndex >= 8)
		{
			bitIndex = 0;
			byteIndex++;
		}

		int bitsToRead = bitCount;
		if (bitsToRead > 8 - bitIndex)
		{
			bitsToRead = 8 - bitIndex;
		}

		const int mask = 0xFF >> bitIndex;
		const int currentByte = (mask & buffer[byteIndex]) >> (8 - bitIndex - bitsToRead);

		value = (value << bitsToRead) | currentByte;
		bitIndex += bitsToRead;
		bitCount -= bitsToRead;
	}
	return value;
}