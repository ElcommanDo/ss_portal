---
language:
- en
metrics:
- accuracy
- precision
- f1
- recall
pipeline_tag: token-classification
library_name: spacy
tags:
- spacy
- nlp
- python
- skill-extraction
- ner
---

# Skill Extraction Model using spaCy

This is a custom **Named Entity Recognition (NER)** model built with **spaCy** to identify and extract skills from resumes and job descriptions.

## Why This Model?

To improve flexibility and accuracy, we transitioned from a static skill extraction approach to a dynamic one. This new method leverages spaCy to fine-tune a pre-trained Named Entity Recognition (NER) model, enabling the extraction of skills directly from resumes and job descriptions. By removing the dependency on predefined skill lists, the model can recognize context-specific, domain-relevant, and even newly emerging skills. This dynamic strategy offers a more adaptive and scalable solution for real-world skill extraction and talent-matching applications.

---

## How to Use

### 1. Load the Model from Hugging Face

```python
from huggingface_hub import snapshot_download
import spacy

# Download the model from the Hub
model_path = snapshot_download("amjad-awad/skill-extractor", repo_type="model")

# Load the model with spaCy
nlp = spacy.load(model_path)

# Example usage
text = "Experienced in Python, JavaScript, and cloud services like AWS and Azure."
doc = nlp(text)

# Extract skill entities
skills = [ent.text for ent in doc.ents if "SKILLS" in ent.label_]
print(skills)
```
```output
['Python', 'JavaScript', 'cloud', 'AWS', 'Azure']
```