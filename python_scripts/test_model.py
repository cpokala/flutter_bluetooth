import logging
from convert_phi_model import test_extraction

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def test_environmental_extraction():
    test_cases = [
        """Extract information from these real-time sensor readings:
        Temperature: 24.5°C
        VOC: 150 ppb
        Humidity: 55%
        Pressure: 1013 hPa
        PM2.5: 12 µg/m³""",

        """Analyze and extract key information from this data:
        VOC Level: 250 ppb
        Temperature: 26°C
        Humidity: 65%
        Pressure: 1015 hPa
        PM10: 25 µg/m³"""
    ]

    logger.info("Running information extraction tests...")

    for i, test_case in enumerate(test_cases, 1):
        logger.info(f"\nTest Case {i}:")
        logger.info(f"Input:\n{test_case}")

        try:
            result = test_extraction(test_case)
            logger.info(f"\nExtracted Information:\n{result}")
        except Exception as e:
            logger.error(f"Error processing test case {i}: {e}")

if __name__ == "__main__":
    test_environmental_extraction()