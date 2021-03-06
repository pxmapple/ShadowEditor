/*
 * Copyright 2003-2006, 2009, 2017, United States Government, as represented by the Administrator of the
 * National Aeronautics and Space Administration. All rights reserved.
 *
 * The NASAWorldWind/WebWorldWind platform is licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */
precision mediump int;

const int FRAGMODE_GROUND_PRIMARY_TEX_BLEND = 4;
const int SAMPLE_COUNT = 2;
const float SAMPLES = 2.0;

const float PI = 3.141592653589;
const float Kr = 0.0025;
const float Kr4PI = Kr * 4.0 * PI;
const float Km = 0.0015;
const float Km4PI = Km * 4.0 * PI;
const float ESun = 15.0;
const float KmESun = Km * ESun;
const float KrESun = Kr * ESun;
const vec3 invWavelength = vec3(5.60204474633241, 9.473284437923038, 19.643802610477206);
const float rayleighScaleDepth = 0.25;

uniform int column;
uniform int row;
uniform int level;
uniform int fragMode;
uniform mat4 mvpMatrix;
uniform mat3 texCoordMatrix;
uniform vec3 vertexOrigin;
uniform vec3 eyePoint;
uniform float eyeMagnitude; /* The eye point's magnitude */
uniform float eyeMagnitude2; /* eyeMagnitude^2 */
uniform vec3 lightDirection; /* The direction vector to the light source */
uniform float atmosphereRadius; /* The outer (atmosphere) radius */
uniform float atmosphereRadius2; /* atmosphereRadius^2 */
uniform float globeRadius; /* The inner (planetary) radius */
uniform float scale; /* 1 / (atmosphereRadius - globeRadius) */
uniform float scaleDepth; /* The scale depth (i.e. the altitude at which
                     the atmosphere's average density is found) */
uniform float scaleOverScaleDepth; /* fScale / fScaleDepth */

attribute vec4 vertexPoint;
attribute vec2 vertexTexCoord;

varying vec3 primaryColor;
varying vec3 secondaryColor;
varying vec2 texCoord;

#define EARTH_RADIUS 6378137.0
#define MIN_LATITUDE -180.0
#define MAX_LATITUDE 180.0
#define MIN_LONGITUDE -180.0
#define MAX_LONGITUDE 180.0
#define PI 3.141592653589793

float scaleFunc(float cos) {
    float x = 1.0 - cos;
    return scaleDepth * exp(-0.00287 + x*(0.459 + x*(3.83 + x*(-6.80 + x*5.25))));
}

void sampleGround() {
    // 每个瓦片位置
    float size = pow(2.0, float(level));
    float dlon = (MAX_LONGITUDE - MIN_LONGITUDE) / size;
    float dlat = (MAX_LATITUDE - MIN_LATITUDE) / size;

    float left = MIN_LONGITUDE + dlon * float(column);
    float top = MAX_LATITUDE - dlat * float(row);
    float right = left + dlon;
    float bottom = top - dlat;

    // 瓦片上每个小格位置
    // +0.5的原因是：position范围是-0.5到0.5
    float lon = left + (right - left) * (0.5 + vertexPoint.x);
    float lat = top - (top - bottom) * (0.5 + vertexPoint.y);

    lon = lon * PI / 180.0;
    lat = lat * PI / 180.0;

    // 墨卡托投影反算
    lat = 2.0 * atan(exp(lat)) - PI / 2.0;

    vec3 transformed = vec3(
        EARTH_RADIUS * cos(lat) * cos(lon),
        EARTH_RADIUS * sin(lat),
        -EARTH_RADIUS * cos(lat) * sin(lon)
    );

    /* Get the ray from the camera to the vertex and its length (which is the far point of the ray passing through the
         atmosphere) */
    vec3 point = transformed.xyz + vertexOrigin;
    vec3 ray = vertexOrigin - eyePoint;
    float far = length(ray);
    ray /= far;
    
    vec3 start;
    if (eyeMagnitude < atmosphereRadius) {
        start = eyePoint;
    } else {
        /* Calculate the closest intersection of the ray with the outer atmosphere (which is the near point of the ray
         passing through the atmosphere) */
        float B = 2.0 * dot(eyePoint, ray);
        float C = eyeMagnitude2 - atmosphereRadius2;
        float det = max(0.0, B*B - 4.0 * C);
        float near = 0.5 * (-B - sqrt(det));
        
        /* Calculate the ray's starting point, then calculate its scattering offset */
        start = eyePoint + ray * near;
        far -= near;
    }
    float depth = exp((globeRadius - atmosphereRadius) / scaleDepth);
    float eyeAngle = dot(-ray, point) / length(point);
    float lightAngle = dot(lightDirection, point) / length(point);
    float eyeScale = scaleFunc(eyeAngle);
    float lightScale = scaleFunc(lightAngle);
    float eyeOffset = depth*eyeScale;
    float temp = (lightScale + eyeScale);
    
    /* Initialize the scattering loop variables */
    float sampleLength = far / SAMPLES;
    float scaledLength = sampleLength * scale;
    vec3 sampleRay = ray * sampleLength;
    vec3 samplePoint = start + sampleRay * 0.5;
    
    /* Now loop through the sample rays */
    vec3 frontColor = vec3(0.0, 0.0, 0.0);
    vec3 attenuate = vec3(0.0, 0.0, 0.0);
    for(int i=0; i<SAMPLE_COUNT; i++) {
        float height = length(samplePoint);
        float depth = exp(scaleOverScaleDepth * (globeRadius - height));
        float scatter = depth*temp - eyeOffset;
        attenuate = exp(-scatter * (invWavelength * Kr4PI + Km4PI));
        frontColor += attenuate * (depth * scaledLength);
        samplePoint += sampleRay;
    }
    
    primaryColor = frontColor * (invWavelength * KrESun + KmESun);
    secondaryColor = attenuate; /* Calculate the attenuation factor for the ground */
}

void main() {
    sampleGround();
    /* Transform the vertex point by the modelview-projection matrix */
    gl_Position = mvpMatrix * vertexPoint;
    if (fragMode == FRAGMODE_GROUND_PRIMARY_TEX_BLEND) {
        /* Transform the vertex texture coordinate by the tex coord matrix */
        texCoord = (texCoordMatrix * vec3(vertexTexCoord, 1.0)).st;
    }
}