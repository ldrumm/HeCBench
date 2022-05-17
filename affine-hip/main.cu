/**********
  Copyright (c) 2017, Xilinx, Inc.
  All rights reserved.

  Redistribution and use in source and binary forms, with or without modification,
  are permitted provided that the following conditions are met:

  1. Redistributions of source code must retain the above copyright notice,
  this list of conditions and the following disclaimer.

  2. Redistributions in binary form must reproduce the above copyright notice,
  this list of conditions and the following disclaimer in the documentation
  and/or other materials provided with the distribution.

  3. Neither the name of the copyright holder nor the names of its contributors
  may be used to endorse or promote products derived from this software
  without specific prior written permission.

  THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
  ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO,
  THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED.
  IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT,
  INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
  PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
  HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
  OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE,
  EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 **********/
#include <sys/types.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <unistd.h>
#include <stdlib.h>
#include <stdio.h>
#include <cstring>
#include <cmath>
#include <iostream>
#include <chrono>
#include <hip/hip_runtime.h>
#include "reference.h"
#include "kernel.h"

int main(int argc, char** argv)
{
  if (argc != 4)
  {
    printf("Usage: %s <input image> <output image> <iterations>\n", argv[0]) ;
    return -1 ;
  }

  unsigned short input_image[Y_SIZE*X_SIZE] __attribute__((aligned(1024)));
  unsigned short output_image[Y_SIZE*X_SIZE] __attribute__((aligned(1024)));
  unsigned short output_image_ref[Y_SIZE*X_SIZE] __attribute__((aligned(1024)));

  // Read the bit map file into memory and allocate memory for the final image
  std::cout << "Reading input image...\n";

  // Load the input image
  const char *inputImageFilename = argv[1];
  FILE *input_file = fopen(inputImageFilename, "rb");
  if (!input_file)
  {
    printf("Error: Unable to open input image file %s!\n", inputImageFilename);
    return 1;
  }

  printf("\n");
  printf("   Reading RAW Image\n");
  size_t items_read = fread(input_image, sizeof(input_image), 1, input_file);
  printf("   Bytes read = %d\n\n", (int)(items_read * sizeof(input_image)));
  fclose(input_file);

  const int iterations = atoi(argv[3]);

  unsigned short *d_input_image;
  hipMalloc((void**)&d_input_image, sizeof(unsigned short)*X_SIZE*Y_SIZE);
  hipMemcpy(d_input_image, input_image, sizeof(unsigned short)*X_SIZE*Y_SIZE, hipMemcpyHostToDevice);

  unsigned short *d_output_image;
  hipMalloc((void**)&d_output_image, sizeof(unsigned short)*X_SIZE*Y_SIZE);

  dim3 grids (32,32);
  dim3 threads (16,16);

  hipDeviceSynchronize();
  auto start = std::chrono::steady_clock::now();

  for (int i = 0; i < iterations; i++) {
    hipLaunchKernelGGL(affine, grids, threads, 0, 0, d_input_image, d_output_image);
  }

  hipDeviceSynchronize();
  auto end = std::chrono::steady_clock::now();
  auto time = std::chrono::duration_cast<std::chrono::nanoseconds>(end - start).count();
  std::cout << "   Average kernel execution time " << (time * 1e-9f) / iterations << " (s)\n";

  hipMemcpy(output_image, d_output_image, sizeof(unsigned short)*X_SIZE*Y_SIZE, hipMemcpyDeviceToHost);
  hipFree(d_input_image);
  hipFree(d_output_image);

  // verify
  affine_reference(input_image, output_image_ref);
  int max_error = 0;
  for (int y = 0; y < 512; y++) {
    for (int x = 0; x < 512; x++) {
      max_error = std::max(max_error, std::abs(output_image[y*512+x] - output_image_ref[y*512+x]));
    }
  }
  printf("   Max output error is %d\n\n", max_error);

  printf("   Writing RAW Image\n");
  const char *outputImageFilename = argv[2];
  FILE *output_file = fopen(outputImageFilename, "wb");
  if (!output_file)
  {
    printf("Error: Unable to write  image file %s!\n", outputImageFilename);
    return 1;
  }
  size_t items_written = fwrite(output_image, sizeof(output_image), 1, output_file);
  printf("   Bytes written = %d\n\n", (int)(items_written * sizeof(output_image)));
  fclose(output_file);

  return 0 ;
}
