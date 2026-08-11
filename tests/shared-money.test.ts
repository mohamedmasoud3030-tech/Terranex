import { describe, expect, it } from 'vitest';
import {
  formatMinorUnits,
  isValidMajorMoney,
  isValidSignedMoney,
  parseMajorUnitsToMinor,
  parseSignedMajorUnitsToMinor,
  INT64_MAX,
} from '../src/shared/money';

describe('shared exact money', () => {
  it('parses user-facing decimal text to bigint minor-unit text without Number arithmetic', () => {
    expect(parseMajorUnitsToMinor('10,000.25', 'EGP')).toBe('1000025');
    expect(parseMajorUnitsToMinor('١٠٠٠٠٫٢٥', 'EGP')).toBe('1000025');
    expect(parseMajorUnitsToMinor('92233720368547758.07', 'EGP')).toBe('9223372036854775807');
    expect(() => parseMajorUnitsToMinor('92233720368547758.08', 'EGP')).toThrow();
    expect(() => parseMajorUnitsToMinor('0', 'EGP')).toThrow();
    expect(() => parseMajorUnitsToMinor('-5', 'EGP')).toThrow();
    expect(() => parseMajorUnitsToMinor('1.005', 'EGP')).toThrow();
  });

  it('parses signed amounts (bank statement semantics) exactly', () => {
    expect(parseSignedMajorUnitsToMinor('-1500', 'EGP')).toBe('-150000');
    expect(parseSignedMajorUnitsToMinor('+2500.50', 'EGP')).toBe('250050');
    expect(parseSignedMajorUnitsToMinor('-10', 'EGP')).toBe('-1000');
    expect(parseSignedMajorUnitsToMinor('-92233720368547758.08', 'EGP')).toBe('-9223372036854775808');
    expect(() => parseSignedMajorUnitsToMinor('92233720368547758.08', 'EGP')).toThrow();
    expect(() => parseSignedMajorUnitsToMinor('12.345', 'EGP')).toThrow();
    expect(parseSignedMajorUnitsToMinor('0', 'EGP')).toBe('0');
  });

  it('formats full int64 values without rejecting them as unsafe JavaScript numbers', () => {
    expect(formatMinorUnits('9223372036854775807', 'EGP')).not.toBe('—');
    expect(formatMinorUnits(INT64_MAX, 'EGP')).not.toBe('—');
    expect(formatMinorUnits(Number.MAX_SAFE_INTEGER + 1, 'EGP')).toBe('—');
  });

  it('formats negative minor units with an explicit sign', () => {
    expect(formatMinorUnits('-150000', 'EGP')).toContain('−');
    expect(formatMinorUnits('-1', 'EGP')).toContain('−');
    expect(formatMinorUnits('0', 'EGP')).not.toContain('−');
  });

  it('validates without throwing', () => {
    expect(isValidMajorMoney('5000.00', 'EGP')).toBe(true);
    expect(isValidMajorMoney('0', 'EGP')).toBe(false);
    expect(isValidSignedMoney('-5000.00', 'EGP')).toBe(true);
    expect(isValidSignedMoney('1.005', 'EGP')).toBe(false);
  });

  it('round-trips decimal text exactly across the int64 range', () => {
    for (const value of ['0.01', '1', '999999999999.99', '1234567890123456.78', '92233720368547758.07']) {
      const minor = parseMajorUnitsToMinor(value, 'EGP');
      expect(minor).toBe(parseMajorUnitsToMinor(value, 'EGP'));
      expect(BigInt(minor)).toBeGreaterThan(0n);
      expect(BigInt(minor)).toBeLessThanOrEqual(INT64_MAX);
    }
  });
});
