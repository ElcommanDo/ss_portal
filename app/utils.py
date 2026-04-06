import pdfplumber
import spacy
import os
from huggingface_hub import snapshot_download

# Download and load the model once when the server starts
MODEL_DIR = os.path.join(os.path.dirname(__file__), 'skill_model')

def load_skill_model():
    if not os.path.exists(MODEL_DIR):
        print("Downloading model...")
        snapshot_download("amjad-awad/skill-extractor", local_dir=MODEL_DIR)
    return spacy.load(MODEL_DIR)

nlp = load_skill_model()

def extract_skills_from_pdf(file_obj):
    text = ""
    with pdfplumber.open(file_obj) as pdf:
        for page in pdf.pages:
            text += page.extract_text() + "\n"
    
    doc = nlp(text)
    # Extract unique skills found by the AI
    skills = list(set([ent.text.strip() for ent in doc.ents if "SKILL" in ent.label_]))
    return skills


def get_priority_color(priority):
    colors = {
        'HIGH': '#ef4444',
        'MEDIUM': '#f59e0b',
        'LOW': '#10b981',
    }
    return colors.get(priority.upper(), '#64748b')


def get_status_color(status):
    status = status.lower()
    if status in ['completed', 'done', 'finished']:
        return '#10b981'      # green
    elif status in ['in progress', 'working']:
        return '#3b82f6'      # blue
    elif status in ['review', 'pending review']:
        return '#8b5cf6'      # purple
    elif status in ['cancelled', 'rejected']:
        return '#ef4444'      # red
    return '#64748b'          # default gray