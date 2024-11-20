import os
import torch
from transformers import AutoTokenizer, AutoModelForCausalLM, pipeline
import json
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def convert_phi_model():
    try:
        # Setup paths
        current_dir = os.path.dirname(os.path.abspath(__file__))
        project_root = os.path.dirname(current_dir)
        output_dir = os.path.join(project_root, 'assets', 'phi_model')
        os.makedirs(output_dir, exist_ok=True)

        logger.info("Starting Phi-3.5-Mini setup for information extraction...")

        # Initialize model and tokenizer
        model_id = "microsoft/phi-3.5-mini"

        logger.info("Loading tokenizer...")
        tokenizer = AutoTokenizer.from_pretrained(model_id)

        # Set padding token
        logger.info("Configuring tokenizer...")
        if tokenizer.pad_token is None:
            tokenizer.pad_token = tokenizer.eos_token
            logger.info("Set padding token to EOS token")

        logger.info("Loading model...")
        model = AutoModelForCausalLM.from_pretrained(
            model_id,
            torch_dtype=torch.float32,
            device_map="auto",  # Automatically choose best device
            trust_remote_code=True
        )

        # Create the pipeline for text generation
        logger.info("Creating text generation pipeline...")
        extraction_pipeline = pipeline(
            "text-generation",
            model=model,
            tokenizer=tokenizer,
            max_new_tokens=512,
            temperature=0.7,
            top_p=0.9,
            repetition_penalty=1.2,
            do_sample=True
        )

        # Test extraction with environmental data
        test_cases = [
            """Extract key information from these sensor readings:
            Temperature: 25.5°C
            Humidity: 60%
            VOC Level: 150 ppb
            Pressure: 1013 hPa

            Format the extracted information and provide insights.""",

            """Analyze this environmental data and extract important details:
            VOC: 250 ppb
            PM2.5: 15 µg/m³
            Temperature: 26°C
            Humidity: 65%
            Pressure: 1015 hPa

            Identify key patterns and potential concerns."""
        ]

        logger.info("\nTesting information extraction...")
        sample_extractions = {
            'test_cases': test_cases,
            'extractions': []
        }

        for test_case in test_cases:
            logger.info(f"\nInput:\n{test_case}")

            result = extraction_pipeline(
                test_case,
                max_length=1024,
                num_return_sequences=1
            )[0]['generated_text']

            logger.info(f"Extracted Information:\n{result}")
            sample_extractions['extractions'].append(result)

        # Save the pipeline configuration
        pipeline_config = {
            'model_name': model_id,
            'max_new_tokens': 512,
            'temperature': 0.7,
            'top_p': 0.9,
            'repetition_penalty': 1.2,
            'do_sample': True
        }

        # Save configurations
        logger.info("\nSaving configurations...")
        with open(os.path.join(output_dir, 'extraction_config.json'), 'w') as f:
            json.dump(pipeline_config, f, indent=2)

        with open(os.path.join(output_dir, 'sample_extractions.json'), 'w') as f:
            json.dump(sample_extractions, f, indent=2)

        # Save model and tokenizer
        logger.info("Saving model and tokenizer...")
        model.save_pretrained(output_dir)
        tokenizer.save_pretrained(output_dir)

        logger.info("\nSetup completed successfully!")
        logger.info(f"Files saved to: {output_dir}")
        logger.info("\nGenerated files:")
        for file in os.listdir(output_dir):
            file_path = os.path.join(output_dir, file)
            size_mb = os.path.getsize(file_path) / (1024 * 1024)
            logger.info(f"- {file} ({size_mb:.2f} MB)")

    except Exception as e:
        logger.error(f"\nError during setup: {str(e)}")
        import traceback
        logger.error(traceback.format_exc())
        raise

def test_extraction(input_text):
    try:
        # Load the saved model and tokenizer
        model_dir = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), 'assets', 'phi_model')

        # Load configurations
        with open(os.path.join(model_dir, 'extraction_config.json'), 'r') as f:
            config = json.load(f)

        # Initialize model and tokenizer
        tokenizer = AutoTokenizer.from_pretrained(model_dir)
        model = AutoModelForCausalLM.from_pretrained(
            model_dir,
            torch_dtype=torch.float32,
            device_map="auto"
        )

        # Create pipeline
        extraction_pipeline = pipeline(
            "text-generation",
            model=model,
            tokenizer=tokenizer,
            **config
        )

        # Run extraction
        result = extraction_pipeline(
            input_text,
            max_length=1024,
            num_return_sequences=1
        )[0]['generated_text']

        return result

    except Exception as e:
        logger.error(f"Error during extraction test: {e}")
        raise

if __name__ == "__main__":
    convert_phi_model()