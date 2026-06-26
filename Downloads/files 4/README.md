# env0 + AWS CDK POC (CloudFormation Custom Flow)

This repository proves that env0 can run an AWS CDK (Python) app through a Custom
Flow. env0 clones the repo, installs the Python dependencies, sets up CDK,
synthesizes the CDK app into CloudFormation, deploys that CloudFormation, lets
you validate the live AWS resources, and destroys everything on teardown.

The workload it deploys is small but real: an Application Load Balanced Fargate
service running a public nginx image. It gives you a public URL you can curl,
and it exercises the full AWS permission set a CDK workload typically needs
(ECS/Fargate, ECR image pulls, VPC networking, security groups, load balancing,
CloudWatch Logs, and IAM role creation with iam:PassRole).

Anyone with an AWS sandbox account and an env0 account can follow this README end
to end. No prior CDK or CloudFormation experience is assumed.

## What gets deployed

A single CloudFormation stack (named WesternUnionCdkPoc) containing about 25
resources:

- A VPC with two public subnets across two availability zones, an internet
  gateway, and route tables. There are no NAT gateways, which keeps cost and
  deploy time low.
- An ECS cluster.
- An Application Load Balanced Fargate service: one task (0.25 vCPU, 0.5 GB)
  running nginx, fronted by an internet-facing Application Load Balancer with a
  listener, target group, and security groups.
- Two IAM roles (the ECS task execution role and the task role) plus one inline
  policy, and a CloudWatch log group.

The stack outputs a ServiceURL. Curling it returns the nginx default page, which
proves the task is running behind the load balancer.

## How it works

This follows the env0-recommended pattern for CDK: set the environment's IaC type
to CloudFormation, and run cdk synth at the earliest Custom Flow hook so the
synthesized template exists before env0 runs its native CloudFormation deploy.

1. The env0 template's IaC type is CloudFormation.
2. The Custom Flow (env0.yml) runs at setupVariables.after, the earliest hook,
   before env0's native CloudFormation steps. It installs the Python
   dependencies and synthesizes the CDK app into a plain CloudFormation template
   at synth/WesternUnionCdkPoc.template.json.
3. env0 then deploys that template with aws cloudformation deploy and manages the
   stack lifecycle natively, so you get change-set review, drift detection, RBAC,
   and a clean destroy.

The app uses CDK's CliCredentialsStackSynthesizer, which produces a self-contained
template with no bootstrap roles, no asset parameters, and no bootstrap-version
rule. Because the workload pulls a public container image at runtime (no Docker
build) and has no file assets, the synthesized template is a plain CloudFormation
document env0 deploys directly. There is no cdk bootstrap step and no S3 asset
bucket to manage.

The template has been validated locally. It synthesizes cleanly, has zero
CloudFormation parameters and zero rules, is about 12 KB (well under the 51,200
byte inline limit, so no S3 staging bucket is needed), and passes cfn-lint with
only a single benign warning (a redundant DependsOn that has no deployment
impact). It selects availability zones with Fn::GetAZs, so it is region-portable.

## Repository layout

```
app.py                                  CDK app entrypoint (the synth target)
western_union_poc/__init__.py           package marker
western_union_poc/fargate_stack.py      the VPC + ECS + ALB + Fargate stack
cdk.json                                CDK config (app command + feature flags)
requirements.txt                        pinned Python deps (aws-cdk-lib, constructs)
env0.yml                                env0 Custom Flow (the synth hook)
scripts/synth.sh                        installs deps and runs the synth
synth/WesternUnionCdkPoc.template.json  committed synth output (regenerated each deploy)
.gitignore
```

## Prerequisites

You need four things before you start. Each is covered in detail in the steps
below.

1. An AWS account, ideally a non-production or sandbox account, plus credentials
   (an access key ID and secret access key) for an IAM principal that can create
   the resources listed under "AWS permissions" below.
2. An env0 account, with a project you can deploy into and the ability to add a
   cloud credential at the organization level. Adding organization credentials
   usually requires an organization admin role, so if you are not an admin, ask
   one to complete Step 3 for you.
3. A Git provider that env0 can read (GitHub, GitLab, Bitbucket, or Azure DevOps),
   connected to your env0 organization, and permission to push a repository to it.
4. Optional, only if you want to validate locally before pushing: Python 3.9 or
   newer and pip on your machine. Node.js is not required.

### AWS permissions

The IAM principal whose keys you use needs permission to create and later delete
everything in the stack. Administrator access in a sandbox account is the
simplest option. If you prefer a scoped policy, it must cover:

- CloudFormation (create, update, describe, and delete stacks and change sets)
- IAM role creation and iam:PassRole
- ECS and Fargate
- ECR (image pulls only; the POC uses a public image, so no push is needed)
- EC2 networking: VPC, subnets, route tables, internet gateway, security groups
- Elastic Load Balancing (Application Load Balancer, listener, target group)
- CloudWatch Logs
- STS (so the deploy can resolve the caller identity)

Secrets Manager, SSM, and KMS are not used by this stack, so you can leave them
out of a scoped policy unless your account defaults require them.

## Step 1: Generate AWS access keys

Skip this if you already have an access key ID and secret for a suitable
principal.

1. Sign in to the AWS console for your sandbox account.
2. Open the IAM console.
3. Go to Users and select your user (or create a user with the permissions
   listed above and select it).
4. Open the Security credentials tab.
5. Under Access keys, choose Create access key, pick the Command Line Interface
   use case, and confirm.
6. Copy the Access key ID and the Secret access key. The secret is shown only
   once, so store it somewhere safe for the moment. You will paste both into env0
   in Step 3 and can then discard your copy.

Decide which region you will deploy into. us-east-1 is a fine default, and the
public image used here is available in every region. Note your choice for Step 4.

## Step 2: Put the code in your Git provider

env0 deploys from a Git repository, so this project needs to live in one.

1. Create a new empty repository in your Git provider (for example, a repo named
   env0-cdk-poc). Do not add a README or .gitignore through the provider's web
   UI, since this project already includes them.
2. From the root of this project on your machine, initialize and push it. Replace
   the remote URL with your new repository's URL:

```
git init
git add .
git commit -m "env0 + AWS CDK POC"
git branch -M main
git remote add origin https://your-git-provider/your-org/env0-cdk-poc.git
git push -u origin main
```

3. Confirm in the provider's web UI that env0.yml and
   synth/WesternUnionCdkPoc.template.json are present at the repository root. Both
   matter: env0 auto-detects env0.yml, and the committed template lets env0
   resolve the CloudFormation file path even before the Custom Flow runs.

## Step 3: Add your AWS credentials to env0

This connects env0 to your AWS account so it can deploy the stack.

1. In env0, open Organization Settings and find the Credentials section (it may
   be labeled Cloud Credentials).
2. Add a new credential of type AWS.
3. Choose the access key option and paste the Access key ID and Secret access key
   from Step 1. Give the credential a clear name, such as "CDK POC sandbox".
4. Save it. You will attach this credential to the environment in Step 4. If your
   env0 setup attaches credentials at the project level, assign it to the project
   you plan to deploy into now.

If you are not an organization admin and cannot see the Credentials section, ask
an admin to add the credential and tell you its name.

## Step 4: Create the env0 environment

Now point env0 at the repository and configure it as a CloudFormation deployment.

1. In env0, open the project you want to deploy into and choose to create a new
   environment (or create a template first, then an environment from it). Connect
   it to the Git repository you pushed in Step 2 and select the main branch.
2. If env0 asks for a working directory, leave it at the repository root, since
   this repo contains only this project.
3. Set the IaC type to CloudFormation.
4. Set the CloudFormation template file path to:

```
synth/WesternUnionCdkPoc.template.json
```

5. Attach the AWS credential you created in Step 3 to this environment (or confirm
   it is attached at the project level).
6. Set the deploy region. Either set it on the AWS credential, or add an
   environment variable named AWS_DEFAULT_REGION with your chosen region (for
   example, us-east-1).
7. Add one more environment variable on the environment. This is the single
   easy-to-miss setting, and the first deploy fails without it because the stack
   creates IAM roles:

```
Name:  ENV0_CF_CLI_ARGS_deploy
Value: --capabilities CAPABILITY_NAMED_IAM
```

8. env0 auto-detects env0.yml at the repository root, so the Custom Flow is picked
   up automatically. There is nothing else to configure for it.

## Step 5: Deploy

1. Trigger a deployment on the environment.
2. In the deployment log you will see the Custom Flow run first: it installs the
   Python dependencies and synthesizes the template. Look for the lines
   "Installing Python CDK dependencies" and "Synth complete".
3. env0 then runs its CloudFormation deploy and presents a change set showing the
   resources it will create.
4. If you have an approval policy enabled, review the change set and approve it.
   Otherwise the deploy proceeds automatically.
5. Wait for the deployment to finish and turn green. The first deploy takes a few
   minutes, mostly while the load balancer and Fargate task come up.

## Step 6: Validate the deployment

1. Open the environment's Outputs (or Resources) tab in env0 and copy the
   ServiceURL value.
2. Curl it from your machine, or open it in a browser:

```
curl http://<the ServiceURL value>
```

You should get the nginx default page (an HTTP 200 with "Welcome to nginx").
That confirms the Fargate task is running and healthy behind the load balancer.

3. If you want to confirm on the AWS side, sign in to the AWS console for the
   target account and region, open CloudFormation, and find the WesternUnionCdkPoc
   stack. You can also see the running service under ECS and the load balancer
   under EC2 Load Balancers.

## Step 7: Destroy

1. Run Destroy on the environment in env0.
2. env0 deletes the CloudFormation stack, which tears down the Fargate service,
   load balancer, VPC, IAM roles, and log group together.
3. Confirm the stack is gone in the CloudFormation console if you want to be sure
   nothing is left running.

Destroying promptly keeps cost near zero. See "Cost and cleanup" below.

## Local validation (optional)

You can synthesize and lint the template on your own machine before pushing, to
confirm everything is wired up. This runs the exact same synth the env0 hook runs.

```
python3 -m pip install -r requirements.txt
python3 app.py
```

That writes synth/WesternUnionCdkPoc.template.json. If Node.js happens to be
installed and you prefer the canonical CDK CLI, you can instead run:

```
npx --yes aws-cdk@2 synth --output synth
```

To structurally validate the template against the CloudFormation spec, install
cfn-lint and run it:

```
python3 -m pip install cfn-lint
cfn-lint synth/WesternUnionCdkPoc.template.json
```

A single W3005 warning about a redundant DependsOn is expected and harmless.

## Configuration reference

Key files:

- app.py builds the CDK app and instantiates the stack with
  CliCredentialsStackSynthesizer, then calls app.synth(). It honors CDK_OUTDIR
  (set by the synth script) and falls back to ./synth.
- western_union_poc/fargate_stack.py defines the VPC, ECS cluster, the
  ApplicationLoadBalancedFargateService, the health check, and the ServiceURL
  output.
- scripts/synth.sh installs requirements with pip and runs python3 app.py, then
  checks that the template was produced.
- env0.yml hooks scripts/synth.sh into setupVariables.after for both deploy and
  destroy.

Environment variables env0 uses:

- ENV0_CF_CLI_ARGS_deploy set to --capabilities CAPABILITY_NAMED_IAM is required,
  because the stack creates IAM roles. CAPABILITY_IAM also works since the roles
  are auto-named, but NAMED_IAM is a safe superset.
- AWS_DEFAULT_REGION optionally sets the deploy region if you do not set it on the
  credential.

Environment variables the synth reads at deploy time (CDK_DEFAULT_ACCOUNT,
CDK_DEFAULT_REGION, AWS_REGION) are populated automatically by the runner, so you
do not need to set them yourself.

## Customizing the workload

- Region: set it on the env0 AWS credential or via AWS_DEFAULT_REGION. The
  template is region-portable, so no code change is needed.
- Container image: change the image in western_union_poc/fargate_stack.py
  (the from_registry call). Any public image that listens on the configured port
  works without further changes. If you switch to a private image in ECR, you will
  also need image-pull permissions and possibly a Docker build step, which is
  beyond this POC.
- Task size: adjust cpu and memory_limit_mib in fargate_stack.py.
- Stack name: change the construct id "WesternUnionCdkPoc" in app.py. If you do,
  update the CloudFormation file path in env0 to match the new template file name
  (CDK names the file after the stack), and update the committed file under synth/.

## How this maps to the lifecycle

- Repo clone: env0 clones the repository at deploy time.
- Python dependency install: scripts/synth.sh runs pip install -r requirements.txt.
- AWS CDK setup: aws-cdk-lib is installed via pip; no Node or cdk CLI is required
  because the synth runs python3 app.py.
- CDK synth: python3 app.py writes synth/WesternUnionCdkPoc.template.json.
- CloudFormation deployment: env0's CloudFormation IaC type runs
  aws cloudformation deploy on the synthesized template.
- Resource validation in AWS: curl the ServiceURL output and inspect the stack in
  the console.
- Destroy and cleanup: env0 Destroy deletes the stack and all its resources.

## Demo talking points

1. Show the repository: it is a normal Python CDK app, with nothing env0-specific
   except the small env0.yml.
2. Kick off the deploy and point out the Custom Flow log lines installing
   dependencies and running synth, then the synthesized CloudFormation appearing.
3. Show env0's change-set review for the CloudFormation stack and approve it.
4. When it is green, curl the ServiceURL to show a live, load-balanced Fargate
   service that env0 deployed straight from CDK code.
5. Run Destroy and show env0 cleanly removing the stack.
6. Close on the value: env0 treats CDK as first-class by compiling it to
   CloudFormation, so teams keep their CDK authoring while gaining env0
   governance, drift detection, RBAC, and change-set review.

## Cost and cleanup

The stack is intentionally cheap: no NAT gateways, one small Fargate task
(0.25 vCPU, 0.5 GB), and one Application Load Balancer. Running cost is a few
cents per hour, dominated by the load balancer. Destroy the environment when you
are done so nothing keeps billing.

## Troubleshooting

- InsufficientCapabilities on deploy: confirm
  ENV0_CF_CLI_ARGS_deploy is set to --capabilities CAPABILITY_NAMED_IAM on the
  environment. This is the most common first-deploy failure.
- env0 cannot find the CloudFormation file when the environment loads: this repo
  commits synth/WesternUnionCdkPoc.template.json specifically so the path always
  resolves before the Custom Flow runs. Do not delete it; the synth step
  overwrites it on every deploy.
- Synth fails on the runner: it only needs Python 3 and pip, which env0 runners
  ship. If you switch scripts/synth.sh to the npx aws-cdk line, the runner also
  needs Node.js.
- Access denied during deploy: the AWS credential lacks one of the permissions
  listed under "AWS permissions". Administrator access in a sandbox account is the
  quickest fix.
- Wrong region or availability zone errors: set the region on the env0 AWS
  credential or via AWS_DEFAULT_REGION. The template itself is region-portable.
- Alternative model: if you would rather have env0 run cdk deploy directly inside
  a Custom Flow instead of deploying the synthesized template, that also works,
  but it uses cdk bootstrap and the standard bootstrap roles, and env0 then treats
  the deployment as a script rather than an env0-managed CloudFormation stack. The
  CloudFormation IaC type approach used here is recommended because it keeps the
  stack fully env0-managed.
