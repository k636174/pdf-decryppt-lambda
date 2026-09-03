FROM public.ecr.aws/lambda/python:3.13

RUN dnf install -y qpdf \
    && dnf clean all

COPY lambda_function.py ${LAMBDA_TASK_ROOT}

CMD ["lambda_function.lambda_handler"]
