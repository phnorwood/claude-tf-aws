#!/usr/bin/env bash
set -euo pipefail

# ─────────────────────────────────────────────
# Static Website Deployment Script
# Provisions AWS infrastructure via Terraform,
# then configures Nginx + Next.js via Ansible.
# ─────────────────────────────────────────────

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TF_DIR="$REPO_ROOT/terraform"
ANSIBLE_DIR="$REPO_ROOT/ansible"

# ── Colours ──────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Colour

info()    { echo -e "${CYAN}[INFO]${NC}  $*"; }
success() { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }

# ── Prerequisites ─────────────────────────────
check_prerequisites() {
  info "Checking prerequisites..."

  for cmd in terraform ansible-playbook aws git; do
    if ! command -v "$cmd" &>/dev/null; then
      error "'$cmd' is not installed or not in PATH."
    fi
  done

  # Verify AWS credentials are configured
  local sts_output sts_exit
  sts_output="$(aws sts get-caller-identity 2>&1)" || sts_exit=$?
  if [[ -n "${sts_exit:-}" ]]; then
    echo -e "${RED}[ERROR]${NC} AWS credentials check failed:" >&2
    echo "$sts_output" >&2
    echo "" >&2
    echo "       Options to configure credentials:" >&2
    echo "         1. aws configure" >&2
    echo "         2. export AWS_ACCESS_KEY_ID=... && export AWS_SECRET_ACCESS_KEY=..." >&2
    echo "         3. export AWS_PROFILE=<profile-name>" >&2
    exit 1
  fi
  info "AWS identity: $(echo "$sts_output" | grep -o '"Arn": "[^"]*"' | cut -d'"' -f4)"

  success "All prerequisites satisfied."
}

# ── Terraform ─────────────────────────────────
terraform_init() {
  info "Initialising Terraform..."
  terraform -chdir="$TF_DIR" init -input=false
  success "Terraform initialised."
}

terraform_plan() {
  info "Running Terraform plan..."
  terraform -chdir="$TF_DIR" plan -out="$TF_DIR/tfplan"
  success "Terraform plan complete."
}

terraform_apply() {
  info "Applying Terraform plan..."
  terraform -chdir="$TF_DIR" apply -input=false "$TF_DIR/tfplan"
  rm -f "$TF_DIR/tfplan"
  success "Terraform apply complete."
}

# ── Fetch Outputs ─────────────────────────────
get_tf_output() {
  terraform -chdir="$TF_DIR" output -raw "$1" 2>/dev/null
}

# ── Wait for SSH ──────────────────────────────
wait_for_ssh() {
  local ip="$1"
  local key="$2"
  local max_attempts=30
  local attempt=0

  info "Waiting for SSH to become available on $ip..."
  until ssh -i "$key" \
            -o StrictHostKeyChecking=no \
            -o ConnectTimeout=5 \
            -o BatchMode=yes \
            ubuntu@"$ip" echo "SSH ready" &>/dev/null; do
    attempt=$((attempt + 1))
    if [[ $attempt -ge $max_attempts ]]; then
      error "SSH did not become available after $max_attempts attempts."
    fi
    echo -n "."
    sleep 5
  done
  echo ""
  success "SSH is available."
}

# ── Ansible ───────────────────────────────────
run_ansible() {
  local playbook="$1"
  local label="$2"

  info "Running Ansible: $label"
  ansible-playbook \
    --inventory "$ANSIBLE_DIR/inventory.ini" \
    "$ANSIBLE_DIR/$playbook"
  success "$label complete."
}

# ── Print Summary ─────────────────────────────
print_summary() {
  local ip="$1"
  echo ""
  echo -e "${GREEN}══════════════════════════════════════════${NC}"
  echo -e "${GREEN}  Deployment complete!${NC}"
  echo -e "${GREEN}══════════════════════════════════════════${NC}"
  echo -e "  Website URL  : ${CYAN}http://$ip${NC}"
  echo -e "  SSH access   : ssh -i ansible/ssh-key.pem ubuntu@$ip"
  echo -e "  Destroy all  : cd terraform && terraform destroy"
  echo -e "${GREEN}══════════════════════════════════════════${NC}"
}

# ── Main ──────────────────────────────────────
main() {
  echo ""
  echo -e "${CYAN}╔══════════════════════════════════════════╗${NC}"
  echo -e "${CYAN}║   Static Website Deployment              ║${NC}"
  echo -e "${CYAN}║   Terraform + Ansible on AWS EC2         ║${NC}"
  echo -e "${CYAN}╚══════════════════════════════════════════╝${NC}"
  echo ""

  check_prerequisites

  # ── Step 1: Provision infrastructure ──
  terraform_init
  terraform_plan

  echo ""
  read -rp "$(echo -e "${YELLOW}Proceed with 'terraform apply'? [y/N]: ${NC}")" confirm
  [[ "${confirm,,}" == "y" ]] || { warn "Aborted by user."; exit 0; }

  terraform_apply

  # ── Step 2: Retrieve outputs ──
  PUBLIC_IP="$(get_tf_output instance_public_ip)"
  SSH_KEY="$ANSIBLE_DIR/ssh-key.pem"

  info "Instance public IP: $PUBLIC_IP"
  info "Inventory written to: $ANSIBLE_DIR/inventory.ini"

  # ── Step 3: Wait for instance to accept SSH ──
  wait_for_ssh "$PUBLIC_IP" "$SSH_KEY"

  # ── Step 4: Configure web server ──
  run_ansible "playbook.yml"     "Nginx installation and website clone"
  run_ansible "build-nextjs.yml" "Node.js install and Next.js build"

  # ── Step 5: Done ──
  print_summary "$PUBLIC_IP"
}

main "$@"
