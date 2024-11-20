import json
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def create_config_files():
    try:
        # Setup paths
        current_dir = os.path.dirname(os.path.abspath(__file__))
        project_root = os.path.dirname(current_dir)
        model_dir = os.path.join(project_root, 'assets', 'phi_model')

        # Create model config
        model_config = {
            "model_type": "phi-3.5-mini",
            "vocab_size": 51200,
            "hidden_size": 2048,
            "num_attention_heads": 32,
            "max_position_embeddings": 2048,
            "pad_token_id": 0,
            "eos_token_id": 2,
            "max_length": 512
        }

        with open(os.path.join(model_dir, 'config.json'), 'w') as f:
            json.dump(model_config, f, indent=2)
            logger.info("Created config.json")

        # Create tokenizer config
        tokenizer_config = {
            "model_max_length": 2048,
            "padding_side": "right",
            "truncation_side": "right",
            "pad_token": "[PAD]",
            "eos_token": "</s>",
            "unk_token": "[UNK]"
        }

        with open(os.path.join(model_dir, 'tokenizer_config.json'), 'w') as f:
            json.dump(tokenizer_config, f, indent=2)
            logger.info("Created tokenizer_config.json")

        # Create environmental analysis config
        env_config = {
            "prompt_template": """Analyze these environmental sensor readings and provide a detailed assessment:

{readings}

Please provide:
1. Air Quality Status: Evaluate the overall air quality based on the readings
2. Health Implications: Identify potential health effects
3. Comfort Level: Assess the comfort conditions
4. Recommended Actions: Suggest specific measures to improve or maintain conditions

Analysis:""",
            "max_length": 512,
            "temperature": 0.7,
            "top_p": 0.9,
            "repetition_penalty": 1.2
        }

        with open(os.path.join(model_dir, 'env_analysis_config.json'), 'w') as f:
            json.dump(env_config, f, indent=2)
            logger.info("Created env_analysis_config.json")

        logger.info("All configuration files created successfully!")

    except Exception as e:
        logger.error(f"Error creating config files: {e}")
        raise

if __name__ == "__main__":
    create_config_files()